require "rails_helper"

RSpec.describe RestrictionPicker do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  let(:sections) { described_class.new.sections }

  # A node left off the page would read as unticked on save and be removed.
  it "lists every node exactly once, the 'common food' umbrella included" do
    names = []
    sections.each { |section| section.entries.each { |entry| entry.each_entry { |each| names << each.node.name } } }
    expect(names.tally.values.uniq).to eq([ 1 ])
    expect(names).to match_array(TaxonomyNode.pluck(:name))
  end

  it "puts allergens first, each group followed by what it covers" do
    expect(sections.first.title).to eq("Egg")
    tree_nut = sections.find { |section| section.title == "Tree nut" }.entries.sole
    expect(tree_nut).to have_attributes(covers_children: true)
    expect(tree_nut.node.name).to eq("tree nut")
    expect(tree_nut.children.map { |entry| entry.node.name }).to include("almond")
  end

  # A flat list made "cheese" look like it covered milk's later items too.
  it "nests a subgroup's items inside it, apart from its siblings" do
    milk = sections.find { |section| section.title == "Milk" }.entries.sole
    cheese = milk.children.find { |entry| entry.node.name == "cheese" }
    under_cheese = cheese.children.map { |entry| entry.node.name }
    expect(under_cheese).to include("parmesan")
    expect(under_cheese).not_to include("cream", "ghee")
    expect(milk.children.map { |entry| entry.node.name }).to include("cheese", "cream")
  end

  # The engine follows memberships too, so the page must say so.
  it "names the foods listed elsewhere that a group also covers" do
    entries = {}
    sections.each { |section| section.entries.each { |entry| entry.each_entry { |each| entries[each.node.name] = each } } }
    expect(entries.fetch("wheat").linked).to include("soy sauce")
    expect(entries.fetch("gluten").linked).to include("oat", "soy sauce")
    expect(entries.fetch("almond").linked).to eq([])
  end

  it "only claims coverage the engine really applies" do
    patient = create(:patient)
    patient.restrictions.create!(kind: "allergy", term: "wheat")
    result = Evaluation::Engine.new([ patient ]).evaluate([ "soy sauce" ])
    expect(result.tier).to eq(Evaluation::Tier::CONFLICT)
  end

  it "splits common foods into their categories" do
    expect(sections.map(&:title)).to include("Poultry", "Vegetables", "Fruits", "Nutrients", "Other foods")
  end
end
