require "rails_helper"

RSpec.describe AvoidList do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  def patient_with(name, **restrictions)
    patient = create(:patient, display_name: name)
    restrictions.each do |kind, terms|
      Array(terms).each { |term| create(:restriction, patient:, kind:, term:) }
    end
    patient.reload
  end

  def section(list, key) = list.sections.find { |each| each.key == key }
  def labels(list, key) = section(list, key).entries.map(&:label)
  def entry(list, label) = list.entries.find { |each| each.label == label }

  let(:ana) { patient_with("Ana Ruiz", allergy: "tree nuts", condition: "low sodium", can: "almond") }
  let(:ben) { patient_with("Ben Okafor", allergy: "nuts", cannot: "shrimp", intolerance: "lactose") }
  let(:cy) { patient_with("Cy Park", cannot: [ "almond flour", "Qwrtp" ], condition: "low salt") }

  it "puts allergy, intolerance and cannot under Avoid, conditions under Limit, cans under Marked OK" do
    list = described_class.build([ ana ])
    expect(list.sections.map(&:title)).to eq([ "Avoid", "Limit", "Marked OK" ])
    expect(labels(list, :avoid)).to eq([ "tree nut" ])
    expect(labels(list, :limit)).to eq([ "sodium" ])
    expect(labels(list, :ok)).to eq([ "almond" ])
    expect(section(list, :ok).note).to include("A can never overrides an allergy")
  end

  it "merges the same node across patients into one entry naming every patient" do
    list = described_class.build([ ana, ben, cy ])
    tree_nut = entry(list, "tree nut")
    expect(list.entries.count { |each| each.label == "tree nut" }).to eq(1)
    expect(tree_nut.patient_names).to eq([ "Ana Ruiz", "Ben Okafor" ])
    expect(tree_nut.kinds).to eq([ "allergy" ])

    sodium = entry(list, "sodium")
    expect(sodium.patient_names).to eq([ "Ana Ruiz", "Cy Park" ])
    expect(sodium.section).to eq(:limit)
  end

  it "keeps a node and its descendant as separate entries" do
    list = described_class.build([ ana, cy ])
    expect(labels(list, :avoid)).to include("tree nut", "almond")
    expect(entry(list, "almond").patient_names).to eq([ "Cy Park" ])
  end

  it "keeps a can apart from an avoid entry for the same node" do
    list = described_class.build([ ana, cy ])
    expect(section(list, :avoid).entries.map(&:label)).to include("almond")
    expect(section(list, :ok).entries.map(&:label)).to eq([ "almond" ])
    expect(section(list, :ok).entries.sole.patient_names).to eq([ "Ana Ruiz" ])
  end

  it "places a node under Avoid when one patient avoids it and another only limits it" do
    a = patient_with("Dee", condition: "soy sauce")
    b = patient_with("Eli", cannot: "soy sauce")
    soy_sauce = entry(described_class.build([ a, b ]), "soy sauce")
    expect(soy_sauce.section).to eq(:avoid)
    expect(soy_sauce.kinds).to eq(%w[cannot condition])
    expect(soy_sauce.needs.map { |need| [ need.patient_name, need.kind ] }).to eq([ %w[Dee condition], %w[Eli cannot] ])
  end

  it "merges unrecognized terms by their normalized text and says how they are checked" do
    other = patient_with("Fay", allergy: "qwrtp!")
    list = described_class.build([ cy, other ])
    qwrtp = list.entries.select { |each| each.node.nil? }
    expect(qwrtp.size).to eq(1)
    expect(qwrtp.sole.label).to eq("Qwrtp")
    expect(qwrtp.sole.patient_names).to eq([ "Cy Park", "Fay" ])
    expect(qwrtp.sole.match_notes).to eq([ "not recognized — checked by exact text only" ])
    expect(qwrtp.sole.section).to eq(:avoid)
  end

  it "flags fuzzy restriction matches for checking" do
    fuzzy = patient_with("Gus", allergy: "almnd")
    almond = described_class.build([ fuzzy ]).entries.sole
    expect(almond.label).to eq("almond")
    expect(almond.match_notes).to eq([ "fuzzy match — please check (you entered 'almnd')" ])
  end

  it "hints at what a node with children includes" do
    hint = entry(described_class.build([ ana ]), "tree nut").hint
    expect(hint).to start_with("includes almond, ")
    expect(hint.delete_prefix("includes ").split(", ").size).to eq(described_class::HINT_SIZE + 1) # six names and "…"
    expect(hint).to end_with("…")
    expect(entry(described_class.build([ ana ]), "sodium").hint).to start_with("includes bacon, cured meat")
    expect(entry(described_class.build([ cy ]), "almond").hint).to be_nil
  end

  it "reports cross-contact when any selected patient has an allergy" do
    expect(described_class.build([ cy ]).cross_contact?).to be(false)
    expect(described_class.build([ cy, ben ]).cross_contact?).to be(true)
  end

  it "stamps profile versions like a group result and goes stale on a change" do
    list = described_class.build([ ana, cy ])
    expect(list.profile_versions).to eq(ana.id => ana.reload.profile_version, cy.id => cy.reload.profile_version)
    expect(list.built_at).to be_within(5.seconds).of(Time.current)
    expect(list.stale?).to be(false)
    create(:restriction, patient: cy, kind: :allergy, term: "egg")
    expect(list.stale?).to be(true)
  end

  it "accepts ids and keeps the selection order, skipping missing ids" do
    list = described_class.build([ cy.id, ana.id, 0 ])
    expect(list.patient_names).to eq([ "Cy Park", "Ana Ruiz" ])
  end

  it "is empty for nobody" do
    list = described_class.build([])
    expect(list).to be_empty
    expect(list.to_terms).to eq([])
    expect(list.cross_contact?).to be(false)
  end

  describe "#to_terms" do
    it "lists sorted, de-duplicated Avoid and Limit terms, leaving out cans" do
      fuzzy = patient_with("Gus", allergy: "almnd")
      terms = described_class.build([ ana, ben, cy, fuzzy ]).to_terms
      expect(terms).to eq([ "almnd", "almond", "lactose", "qwrtp", "shrimp", "sodium", "tree nut" ])
    end

    it "never contains a patient's display name, even when a name looks like a term" do
      tricky = patient_with("Almond Shrimp", allergy: "peanut", can: "Almond Shrimp")
      patients = [ ana, ben, cy, tricky ]
      terms = described_class.build(patients).to_terms
      text = terms.join(" ")
      patients.each { |patient| expect(text).not_to include(patient.display_name) }
      expect(terms).to all(be_a(String))
      expect(terms.grep(/\A\d+\z/)).to be_empty
    end
  end
end
