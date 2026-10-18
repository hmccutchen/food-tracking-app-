require "rails_helper"

RSpec.describe RestrictionSelection do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  let(:patient) { create(:patient) }

  def node(name) = TaxonomyNode.find_by!(name:)
  def selection(kind = "allergy") = described_class.new(patient, kind)

  it "adds one manual restriction per ticked node" do
    result = selection.update([ node("almond").id, node("milk").id ])
    expect(result.added).to eq(%w[almond milk])
    expect(patient.restrictions.allergy.map { |r| [ r.term, r.taxonomy_node, r.match_type, r.match_reason ] })
      .to contain_exactly([ "almond", node("almond"), "manual", "set by you" ], [ "milk", node("milk"), "manual", "set by you" ])
  end

  it "removes the restrictions whose node was unticked, and keeps the rest" do
    selection.update([ node("almond").id, node("milk").id ])
    result = selection.update([ node("milk").id, node("egg").id ])
    expect(result).to have_attributes(added: [ "egg" ], removed: [ "almond" ])
    expect(patient.restrictions.allergy.map(&:term)).to contain_exactly("milk", "egg")
  end

  it "counts a typed restriction that matched a node as ticked, and removes it when unticked" do
    patient.restrictions.create!(kind: "allergy", term: "no nuts", note: "carries an EpiPen")
    expect(selection.selected_node_ids).to eq(Set[node("tree nut").id])
    expect(selection.noted_node_ids).to eq(Set[node("tree nut").id])
    expect(selection.update([]).removed).to eq([ "no nuts" ])
    expect(patient.restrictions.reload).to be_empty
  end

  it "never touches typed terms that weren't recognized, or other kinds" do
    patient.restrictions.create!(kind: "allergy", term: "grandma's stew")
    patient.restrictions.create!(kind: "cannot", term: "shrimp")
    selection.update([])
    expect(patient.restrictions.map(&:term)).to contain_exactly("grandma's stew", "shrimp")
    expect(selection.unmatched.map(&:term)).to eq([ "grandma's stew" ])
  end

  it "ignores unknown ids and blanks" do
    expect(selection.update([ "", "0", node("egg").id.to_s ]).added).to eq([ "egg" ])
  end

  it "reports no change when nothing changed, and leaves the profile version alone" do
    selection.update([ node("egg").id ])
    expect { expect(selection.update([ node("egg").id ])).not_to be_changed }.not_to(change { patient.reload.profile_version })
  end

  it "bumps the profile version when the set changes, so older results go out of date" do
    expect { selection.update([ node("egg").id ]) }.to(change { patient.reload.profile_version })
  end

  it "feeds the engine like restrictions added one by one" do
    selection.update([ node("tree nut").id ])
    result = Evaluation::Engine.new([ patient.reload ]).evaluate([ "almond flour" ])
    expect(result.tier).to eq(Evaluation::Tier::CONFLICT)
  end

  it "rejects an unknown kind" do
    expect { described_class.new(patient, "maybe") }.to raise_error(ArgumentError)
  end

  it "names the kind without the list heading's note" do
    expect(selection("can").heading).to eq("Can have")
    expect(selection("allergy").heading).to eq("Allergies")
  end
end
