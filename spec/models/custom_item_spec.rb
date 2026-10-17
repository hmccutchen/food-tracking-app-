require "rails_helper"

RSpec.describe CustomItem do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  let(:user) { create(:user) }
  let(:patient) { create(:patient, user:) }
  let(:conflict) { Evaluation::Tier::CONFLICT }
  let(:unknown) { Evaluation::Tier::UNKNOWN }

  def node(name) = TaxonomyNode.find_by!(name:)

  def add(**attributes)
    item = described_class.new(user:, **attributes)
    expect(item.save).to be(true), item.errors.full_messages.to_sentence
    item
  end

  def result_for(patient, ingredients)
    Evaluation::Engine.new([ patient ]).evaluate(ingredients).patient_results.sole
  end

  describe "saving" do
    it "creates a custom node owned by the nurse, keeping the ingredient text verbatim" do
      item = add(name: "Mrs. P's soup", ingredients_text: "Contains: wheat flour, MILK", parent_id: node("stock").id,
        aliases_text: "p soup, Mrs P soup")
      expect(item.node).to have_attributes(name: "mrs p's soup", source: "custom", created_by: user, custom?: true,
        ingredients_text: "Contains: wheat flour, MILK", parent: node("stock"))
      expect(item.node.aliases.pluck(:term)).to contain_exactly("p soup", "mrs p soup")
      expect(user.custom_items).to eq([ item.node ])
    end

    it "requires a name" do
      item = described_class.new(user:, name: " ")
      expect(item.save).to be(false)
      expect(item.errors[:name]).to be_present
    end

    it "refuses a name or alias already in the taxonomy" do
      expect(described_class.new(user:, name: "Milk").save).to be(false)
      item = described_class.new(user:, name: "nut milk thing", aliases_text: "almond milk")
      expect(item.save).to be(false)
      expect(item.errors.full_messages.to_sentence).to include("'almond milk' is already another name for 'almond'")
      expect(described_class.new(user:, name: "almond milk").save).to be(false)
    end

    it "only accepts a parent from the list (seeded nodes or her own items)" do
      other = described_class.new(user: create(:user), name: "their thing")
      other.save
      item = described_class.new(user:, name: "mine", parent_id: other.node.id)
      expect(item.save).to be(false)
      expect(item.errors[:parent_id]).to be_present
    end

    it "stores what the ingredient text names as groups the item is a member of" do
      item = add(name: "Mrs. P's soup", ingredients_text: "contains wheat flour, milk, xyzzy gum")
      groups = item.node.groups.pluck(:name)
      expect(groups).to include("wheat", "milk", "lactose")
      expect(item.unrecognized_ingredients).to eq([ "xyzzy gum" ])
    end
  end

  describe "membership direction" do
    let(:item) { add(name: "Mrs. P's soup", ingredients_text: "contains wheat flour, milk").node }

    it "is covered BY the nodes in its ingredient text, not the other way round" do
      expect(node("milk").covers?(item)).to be(true)
      expect(node("wheat").covers?(item)).to be(true)
      expect(node("gluten").covers?(item)).to be(true)
      expect(node("lactose").covers?(item)).to be(true)
      expect(item.covers?(node("milk"))).to be(false)
    end

    it "makes milk and wheat restrictions flag the item in the engine" do
      item
      milk = create(:patient, user:).tap { |p| p.restrictions.create!(kind: :allergy, term: "milk") }
      gluten = create(:patient, user:).tap { |p| p.restrictions.create!(kind: :intolerance, term: "gluten") }
      lactose = create(:patient, user:).tap { |p| p.restrictions.create!(kind: :intolerance, term: "lactose intolerance") }
      [ milk, gluten, lactose ].each { |p| expect(result_for(p.reload, [ "Mrs. P's soup" ]).tier).to eq(conflict) }
    end

    it "keeps a can or cannot on the item to the item itself" do
      item
      patient.restrictions.create!(kind: :cannot, term: item.name, manual_node_id: item.id)
      expect(result_for(patient.reload, [ "milk" ]).flags).to be_empty
    end

    it "takes the tree parent's coverage too" do
      zaatar = add(name: "za'atar", parent_id: node("sesame").id).node
      expect(node("sesame").covers?(zaatar)).to be(true)
    end

    it "flags an item whose ingredient text lists an ambiguous ingredient" do
      add(name: "aunt v's rub", ingredients_text: "natural flavors")
      patient.restrictions.create!(kind: :allergy, term: "peanut")
      flags = result_for(patient.reload, [ "aunt v's rub" ]).flags
      expect(flags.map(&:source)).to eq([ :ambiguous ])
    end
  end

  describe "resolution" do
    it "makes a previously unresolved term resolvable (name and aliases)" do
      expect(Taxonomy::Resolver.new.resolve("mrs p's soup")).to be_unresolved
      item = add(name: "Mrs P's soup", aliases_text: "p soup")
      expect(Taxonomy::Resolver.new.resolve("Mrs. P's soup")).to have_attributes(node: item.node, match_type: :exact)
      expect(Taxonomy::Resolver.new.resolve("P soups")).to have_attributes(node: item.node, match_type: :alias)
    end

    it "re-resolves her unresolved restrictions and bumps those profiles" do
      restriction = patient.restrictions.create!(kind: :cannot, term: "Mrs P's soup")
      expect(restriction.match_type).to eq("unresolved")
      expect { add(name: "mrs p's soup") }.to change { patient.reload.profile_version }
      expect(restriction.reload).to have_attributes(match_type: "exact", taxonomy_node: node("mrs p's soup"))
    end

    it "leaves other nurses' restrictions alone" do
      other = create(:restriction, kind: :cannot, term: "mrs p's soup")
      add(name: "mrs p's soup")
      expect(other.reload.match_type).to eq("unresolved")
    end

    it "re-resolves restrictions that matched an alias she removed" do
      item = add(name: "mrs p's soup", aliases_text: "p soup")
      restriction = patient.restrictions.create!(kind: :cannot, term: "p soup")
      expect(restriction.taxonomy_node).to eq(item.node)
      item.assign_attributes(aliases_text: "")
      expect(item.save).to be(true)
      expect(restriction.reload.match_type).not_to eq("alias") # now fuzzy at best
    end

    it "turns an unknown ingredient into a real tier once added" do
      patient.restrictions.create!(kind: :allergy, term: "milk")
      expect(result_for(patient.reload, [ "mrs p's soup" ]).tier).to eq(unknown)
      add(name: "mrs p's soup", ingredients_text: "milk")
      expect(result_for(patient.reload, [ "mrs p's soup" ]).tier).to eq(conflict)
    end
  end

  describe "per-patient can and cannot" do
    let(:item) { add(name: "Mrs. P's soup", ingredients_text: "contains milk") }

    it "writes ordinary manual restrictions and bumps the profile" do
      expect { item.update_marks(patient.id.to_s => "cannot") }.to change { patient.reload.profile_version }
      expect(patient.restrictions.sole).to have_attributes(kind: "cannot", term: "mrs p's soup", match_type: "manual",
        taxonomy_node: item.node)
      expect(item.marks).to eq(patient.id => "cannot")

      item.update_marks(patient.id.to_s => "can")
      expect(patient.restrictions.reload.sole.kind).to eq("can")
      item.update_marks(patient.id.to_s => "")
      expect(patient.restrictions.reload).to be_empty
    end

    it "ignores patients that aren't hers" do
      stranger = create(:patient)
      item.update_marks(stranger.id.to_s => "cannot")
      expect(stranger.restrictions).to be_empty
    end

    it "a cannot on the item yields a conflict" do
      item.update_marks(patient.id.to_s => "cannot")
      result = result_for(patient.reload, [ "Mrs. P's soup" ])
      expect(result.tier).to eq(conflict)
      expect(result.active_flags.map(&:source)).to eq([ :cannot ])
    end

    it "a can on an item containing milk never silences a milk allergy" do
      patient.restrictions.create!(kind: :allergy, term: "milk")
      item.update_marks(patient.id.to_s => "can")
      result = result_for(patient.reload, [ "Mrs. P's soup" ])
      expect(result.tier).to eq(conflict)
      expect(result.active_flags.map(&:reason)).to eq([ "Mrs. P's soup is in the milk group (allergy)" ])
      expect(result.overridden_flags.map(&:reason).sole).to include("you marked 'mrs p's soup' as can")
    end

    it "keeps marks named after the item when it is renamed" do
      item.update_marks(patient.id.to_s => "cannot")
      item.assign_attributes(name: "Mrs. P's broth")
      item.save
      expect(patient.restrictions.sole).to have_attributes(term: "mrs p's broth", match_type: "manual")
    end
  end

  describe "deleting" do
    it "sends restrictions that used it back to text matching and bumps versions" do
      item = add(name: "mrs p's soup")
      matched = patient.restrictions.create!(kind: :allergy, term: "mrs p's soup")
      item.update_marks(patient.id.to_s => "cannot")
      bystander = create(:patient, user:)

      expect { item.destroy! }.to change { bystander.reload.profile_version }
      expect(TaxonomyNode.exists?(item.node.id)).to be(false)
      expect(patient.restrictions.reload.map { |r| [ r.kind, r.match_type, r.taxonomy_node_id ] })
        .to contain_exactly([ "allergy", "unresolved", nil ], [ "cannot", "unresolved", nil ])
      expect(matched.reload.match_reason).to include("not recognized")

      flags = result_for(patient.reload, [ "mrs p's soup" ]).active_flags
      expect(flags.map(&:reason)).to include("mrs p's soup: text match to 'mrs p's soup' (cannot)")
    end
  end

  describe "the seed loader" do
    it "never deletes or modifies custom nodes, their aliases or memberships" do
      item = add(name: "mrs p's soup", ingredients_text: "milk, broth", parent_id: node("stock").id,
        aliases_text: "p soup").node
      before = [ item.reload.attributes, item.aliases.pluck(:term), item.memberships.pluck(:group_id).sort ]
      expect(item.groups.pluck(:name)).to include("milk", "lactose", "sodium")

      Taxonomy::Seed.load!

      item.reload
      expect([ item.attributes, item.aliases.pluck(:term), item.memberships.pluck(:group_id).sort ]).to eq(before)
    end

    it "keeps the nurse's version when the tree reuses a custom name or alias" do
      item = add(name: "mrs p's soup", aliases_text: "p soup").node
      tree = { "soups" => { kind: :category, aliases: [ "p soup" ], children: { "mrs p's soup" => { kind: :allergen } } } }
      Taxonomy::Seed.load!(tree)
      expect(item.reload).to have_attributes(kind: "ingredient", parent_id: nil, source: "custom")
      expect(TaxonomyAlias.find_by!(term: "p soup").taxonomy_node).to eq(item)
    end
  end
end
