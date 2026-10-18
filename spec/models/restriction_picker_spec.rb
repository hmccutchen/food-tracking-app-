require "rails_helper"

RSpec.describe RestrictionPicker do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  let(:sections) { described_class.new.sections }

  it "lists every node except the 'common food' umbrella exactly once" do
    names = sections.flat_map { |section| section.entries.map { |entry| entry.node.name } }
    expect(names.tally.values.uniq).to eq([ 1 ])
    expect(names).to match_array(TaxonomyNode.where.not(name: "common food").pluck(:name))
  end

  it "puts allergens first, each group followed by what it covers" do
    expect(sections.first.title).to eq("Egg")
    tree_nut = sections.find { |section| section.title == "Tree nut" }
    expect(tree_nut.entries.first).to have_attributes(covers_children: true)
    expect(tree_nut.entries.first.node.name).to eq("tree nut")
    expect(tree_nut.entries.map { |entry| entry.node.name }).to include("almond")
  end

  it "splits common foods into their categories" do
    expect(sections.map(&:title)).to include("Poultry", "Vegetables", "Fruits", "Nutrients", "Other foods")
  end
end
