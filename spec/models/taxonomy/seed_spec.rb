require "rails_helper"

RSpec.describe Taxonomy::Seed do
  before { described_class.load! }

  def node(name) = TaxonomyNode.find_by!(name:)

  it "is idempotent" do
    counts = [ TaxonomyNode.count, TaxonomyAlias.count, TaxonomyMembership.count ]
    described_class.load!
    expect([ TaxonomyNode.count, TaxonomyAlias.count, TaxonomyMembership.count ]).to eq(counts)
  end

  it "drops a stale alias that is spelled like a node" do
    TaxonomyAlias.create!(term: "parmesan-old", taxonomy_node: node("cheese")).update_column(:term, "parmesan")
    described_class.load!
    expect(TaxonomyAlias.exists?(term: "parmesan")).to be(false)
    expect(node("parmesan").parent).to eq(node("cheese"))
  end

  it "restores a node's parent and kind when they drift" do
    node("almond").update!(parent: nil, kind: :category)
    described_class.load!
    expect(node("almond")).to have_attributes(parent: node("tree nut"), kind: "ingredient")
  end

  it "seeds the FDA top 9 allergens" do
    expect(TaxonomyNode.allergen.where(parent_id: nil).or(TaxonomyNode.where(name: "wheat")).pluck(:name))
      .to contain_exactly("milk", "egg", "fish", "shellfish", "tree nut", "peanut", "wheat", "soy", "sesame")
  end

  it "keeps peanut separate from tree nut" do
    expect(node("peanut").parent).to be_nil
    expect(node("tree nut").covers?(node("peanut"))).to be(false)
  end

  it "models gluten as a category covering wheat, barley, rye and malt" do
    gluten = node("gluten")
    expect(gluten).to be_category
    %w[wheat barley rye malt semolina].each { |name| expect(gluten.covers?(node(name))).to be(true), name }
    expect(node("wheat")).to be_allergen
  end

  it "makes lactose an intolerance under milk" do
    expect(node("lactose")).to have_attributes(kind: "intolerance", parent: node("milk"))
  end

  it "has an ambiguous-ingredient category" do
    expect(node("ambiguous ingredient").children.pluck(:name))
      .to contain_exactly("natural flavors", "spices", "stock", "seasoning", "baked beans")
  end

  describe "common foods" do
    let(:common) { node("common food") }
    let(:common_ids) { TaxonomyNode.find_by_sql([ TaxonomyNode::DESCENDANTS_SQL, { id: common.id } ]).map(&:id) }
    let(:common_nodes) { TaxonomyNode.where(id: common_ids) }

    # Every name and alias in a tree, normalized, with where it came from.
    def terms(tree, out = Hash.new { |hash, key| hash[key] = [] })
      tree.each do |name, spec|
        out[Taxonomy::Normalizer.call(name)] << name
        spec.fetch(:aliases, []).each { |term| out[Taxonomy::Normalizer.call(term)] << "alias #{term} of #{name}" }
        terms(spec.fetch(:children, {}), out)
      end
      out
    end

    it "seeds about 200 single foods, all ingredients, in common-prefixed sub-categories" do
      foods = common_nodes.ingredient
      expect(foods.count).to be_between(190, 230)
      expect(common_nodes.where.not(kind: %w[ingredient category]).pluck(:name)).to be_empty
      expect(common.children.pluck(:kind).uniq).to eq([ "category" ])
      expect(common.children.pluck(:name)).to all(start_with("common "))
      %w[chicken beef rice quinoa black\ bean garlic blueberry lemon basil olive\ oil water].each do |name|
        expect(common.covers?(node(name))).to be(true), name
        expect(node(name)).to be_ingredient
      end
    end

    it "has no duplicate name or alias anywhere in the seed" do
      duplicates = terms(described_class.data).select { |_, sources| sources.size > 1 }
      expect(duplicates).to be_empty
      expect(TaxonomyNode.count + TaxonomyAlias.count).to eq(terms(described_class.data).size)
    end

    it "has no mixed or processed items" do
      deny = /\b(sauce|bread|breads|noodle|noodles|pasta|seasoning|spice mix|broth|stock|mix|blend|sausage|sausages|
               dressing|paste|curry|bouillon|chips|crackers|cereal|tortilla|juice drink)\b/x
      names = common_nodes.pluck(:name) + TaxonomyAlias.where(taxonomy_node_id: common_ids).pluck(:term)
      expect(names.grep(deny)).to be_empty
    end

    it "keeps allergen-related foods under their allergen, not under common food" do
      { "peanut oil" => "peanut", "pine nut" => "tree nut", "walnut oil" => "tree nut", "bulgur" => "wheat",
        "farro" => "wheat", "soybean oil" => "soy", "buttermilk" => "milk", "sesame oil" => "sesame" }.each do |text, allergen|
        resolved = Taxonomy::Resolver.new.resolve(text).node
        expect(node(allergen).covers?(resolved)).to be(true), "#{text} → #{allergen}"
        expect(common_ids).not_to include(resolved.id), text
      end
    end

    it "puts oats in the gluten group by membership, not under wheat" do
      oat = node("oat")
      expect(common.covers?(oat)).to be(true)
      expect(node("gluten").members).to include(oat)
      expect(node("gluten").covers?(oat)).to be(true)
      expect(node("wheat").covers?(oat)).to be(false)
    end

    it "keeps coconut a common food, not a tree nut" do
      expect(common.covers?(node("coconut"))).to be(true)
      expect(node("tree nut").covers?(node("coconut"))).to be(false)
    end

    it "adds clear high-potassium foods to potassium, and sugar or sodium only where clear" do
      [ "sweet potato", "black bean", "lentil", "dried apricot", "raisin", "cantaloupe" ].each do |name|
        expect(node("potassium").covers?(node(name))).to be(true), name
      end
      expect(node("potassium").covers?(node("apricot"))).to be(false)
      expect(node("added sugar").covers?(node("dried cranberry"))).to be(true)
      expect(node("sodium").covers?(node("baking soda"))).to be(true)
      expect(node("sodium").covers?(node("olive oil"))).to be(false)
      %w[chicken rice garlic blueberry].each do |name|
        expect(TaxonomyMembership.where(node: node(name))).to be_empty, name
      end
    end

    it "leaves a nurse's custom item alone when reloading" do
      custom = TaxonomyNode.create!(name: "grandma's chili", kind: :ingredient, source: "custom")
      described_class.load!
      expect(custom.reload).to have_attributes(parent: nil, source: "custom")
    end
  end

  describe "descriptor words" do
    it "seeds the defaults once and keeps the nurse's changes" do
      expect(IngredientDescriptor.active.pluck(:word)).to include("diced", "extra-virgin", "cups", "of")
      IngredientDescriptor.find_by!(word: "light").update!(active: false)
      expect { described_class.load! }.not_to change(IngredientDescriptor, :count)
      expect(IngredientDescriptor.find_by!(word: "light")).not_to be_active
    end

    it "never seeds a word that changes or hides the food" do
      expect(IngredientDescriptor.pluck(:word) & IngredientDescriptor::NEVER).to be_empty
      expect(IngredientDescriptor.pluck(:word)).not_to include("canned")
    end
  end

  describe "nutrient groups for conditions" do
    let(:resolver) { Taxonomy::Resolver.new }

    it "seeds sodium, added sugar and potassium as nutrients" do
      expect(TaxonomyNode.nutrient.pluck(:name)).to contain_exactly("sodium", "added sugar", "potassium")
    end

    it "covers soy sauce from sodium via membership and from soy via the tree" do
      soy_sauce = node("soy sauce")
      expect(soy_sauce.parent).to eq(node("soy"))
      expect(node("soy").covers?(soy_sauce)).to be(true)
      expect(node("sodium").covers?(soy_sauce)).to be(true)
      expect(node("sodium").members).to include(soy_sauce)
    end

    it "covers every listed member of each group" do
      {
        "sodium" => [ "fish sauce", "stock", "bacon", "ham", "cured meat", "pickles", "olives", "parmesan" ],
        "added sugar" => [ "honey", "maple syrup", "corn syrup", "molasses", "agave" ],
        "potassium" => %w[banana potato tomato orange avocado spinach]
      }.each do |group, members|
        members.each { |member| expect(node(group).covers?(node(member))).to be(true), "#{group} → #{member}" }
      end
    end

    it "covers what sits under a member in the tree, and through a membership on an ancestor" do
      expect(node("sodium").covers?(node("bacon"))).to be(true)
      node("cured meat").children.create!(name: "chorizo")
      expect(node("sodium").covers?(node("chorizo"))).to be(true)
    end

    it "does not cover unrelated nodes" do
      expect(node("sodium").covers?(node("almond"))).to be(false)
      expect(node("sodium").covers?(node("soy"))).to be(false)
      expect(node("soy").covers?(node("ham"))).to be(false)
      expect(node("potassium").covers?(node("honey"))).to be(false)
      expect(node("milk").covers?(node("olives"))).to be(false)
      expect(node("parmesan").covers?(node("sodium"))).to be(false)
    end

    it "keeps parmesan under milk while it counts toward sodium" do
      expect(node("milk").covers?(node("parmesan"))).to be(true)
    end

    it "resolves condition wording to the group" do
      {
        "low sodium" => "sodium", "Low Salt" => "sodium", "no salt" => "sodium", "hypertension" => "sodium",
        "heart failure" => "sodium", "salt restriction" => "sodium",
        "diabetic" => "added sugar", "Diabetes" => "added sugar", "no sugar" => "added sugar", "low sugar" => "added sugar",
        "renal diet" => "potassium", "CKD" => "potassium", "kidney disease" => "potassium", "low potassium" => "potassium"
      }.each { |text, name| expect(resolver.resolve(text).node).to eq(node(name)), text }
    end

    it "unlinks a member that is removed from the list" do
      tree = described_class.data.merge("potassium" => described_class.data["potassium"].merge(members: [ "banana" ]))
      described_class.load!(tree)
      expect(node("potassium").members).to contain_exactly(node("banana"))
      expect(node("potassium").covers?(node("spinach"))).to be(false)
    end
  end
end
