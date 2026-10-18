require "rails_helper"

RSpec.describe Restriction do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  def node(name) = TaxonomyNode.find_by!(name:)

  subject(:restriction) { build(:restriction) }

  it { is_expected.to belong_to(:patient) }
  it { is_expected.to belong_to(:taxonomy_node).optional }
  it { is_expected.to validate_presence_of(:term) }

  it "requires a valid kind" do
    expect(build(:restriction, kind: nil)).not_to be_valid
    expect(build(:restriction, kind: "preference")).not_to be_valid
    %w[allergy intolerance condition cannot can].each { |kind| expect(build(:restriction, kind:)).to be_valid, kind }
  end

  it "stores kind as a string" do
    expect(create(:restriction, kind: :cannot).kind_before_type_cast).to eq("cannot")
  end

  describe "encryption" do
    def raw(column, id) = ActiveRecord::Base.connection.select_value("SELECT #{column} FROM restrictions WHERE id = #{id.to_i}")

    it "stores term and note encrypted and keeps taxonomy_node_id plaintext" do
      record = create(:restriction, term: "almond flour", note: "anaphylaxis in 2019")
      expect(raw(:term, record.id)).not_to include("almond")
      expect(raw(:note, record.id)).not_to include("anaphylaxis")
      expect(raw(:taxonomy_node_id, record.id)).to eq(node("almond").id)
      expect(record.reload).to have_attributes(term: "almond flour", note: "anaphylaxis in 2019")
    end
  end

  describe "resolution" do
    it "stores an exact match" do
      record = create(:restriction, term: "Tree Nuts")
      expect(record).to have_attributes(taxonomy_node: node("tree nut"), match_type: "exact",
        match_reason: "matched to tree nut")
    end

    it "stores an alias match in plain words" do
      record = create(:restriction, term: "almond flour")
      expect(record).to have_attributes(taxonomy_node: node("almond"), match_type: "alias",
        match_reason: "alias 'almond flour' → almond")
    end

    it "flags a fuzzy match for checking" do
      record = create(:restriction, term: "almnd")
      expect(record).to have_attributes(taxonomy_node: node("almond"), match_type: "fuzzy",
        match_reason: "fuzzy match to almond — please check")
    end

    it "saves an unresolved term without blocking" do
      record = create(:restriction, term: "xyzzy")
      expect(record).to be_persisted
      expect(record).to have_attributes(taxonomy_node: nil, match_type: "unresolved",
        match_reason: "not recognized — will be checked by exact text only")
    end

    it "resolves conditions through the nutrient groups" do
      record = create(:restriction, kind: :condition, term: "low sodium")
      expect(record.taxonomy_node).to eq(node("sodium"))
      expect(record.taxonomy_node.covers?(node("soy sauce"))).to be(true)
    end

    it "re-resolves when the term changes" do
      record = create(:restriction, term: "milk")
      record.update!(term: "almond flour")
      expect(record).to have_attributes(taxonomy_node: node("almond"), match_type: "alias")
    end

    it "does not re-resolve when only the note changes" do
      record = create(:restriction, term: "milk")
      record.update_columns(match_reason: "kept")
      record.update!(note: "only the note")
      expect(record.reload.match_reason).to eq("kept")
    end
  end

  describe "manual node choice" do
    let(:record) { create(:restriction, term: "my own word", manual_node_id: node("sesame").id) }

    it "stores the node as manual, set by you" do
      expect(record).to have_attributes(taxonomy_node: node("sesame"), match_type: "manual", match_reason: "set by you")
    end

    it "keeps the manual node when only the note changes" do
      record.update!(note: "from the form", manual_node_id: node("sesame").id)
      record.update!(note: "from code")
      expect(record.reload).to have_attributes(taxonomy_node: node("sesame"), match_type: "manual")
    end

    it "keeps the manual node when the term changes while the node is still chosen" do
      record.update!(term: "milk", manual_node_id: node("sesame").id)
      expect(record.reload).to have_attributes(taxonomy_node: node("sesame"), match_type: "manual")
    end

    it "keeps the manual node when the term changes and no choice is given" do
      record.update!(term: "milk")
      expect(record.reload).to have_attributes(taxonomy_node: node("sesame"), match_type: "manual")
    end

    it "re-resolves when the nurse clears the choice" do
      record.update!(term: "milk", manual_node_id: "")
      expect(record.reload).to have_attributes(taxonomy_node: node("milk"), match_type: "exact")
    end

    it "switches to another chosen node" do
      record.update!(manual_node_id: node("egg").id)
      expect(record.reload.taxonomy_node).to eq(node("egg"))
    end

    it "preselects the manual node, and nothing for an automatic match" do
      expect(described_class.find(record.id).manual_node_id).to eq(node("sesame").id)
      expect(create(:restriction, term: "milk").manual_node_id).to be_nil
    end

    it "rejects a node that does not exist" do
      bad = build(:restriction, manual_node_id: 0)
      expect(bad).not_to be_valid
      expect(bad.errors[:taxonomy_node]).to be_present
    end
  end
end
