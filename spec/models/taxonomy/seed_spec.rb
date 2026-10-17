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
      .to contain_exactly("natural flavors", "spices", "stock", "seasoning")
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
