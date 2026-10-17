require "rails_helper"

RSpec.describe Usda::Relinker do
  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  it "re-links foods after the taxonomy grows and only writes changed rows" do
    pork = create(:food, description: "Pork, loin, boneless, raw")
    honey = create(:food, description: "Honey", taxonomy_node: TaxonomyNode.find_by!(name: "honey"),
      match_type: "exact", match_reason: "matched to honey via 'honey'")
    TaxonomyNode.create!(name: "pork", kind: :ingredient)

    summary = described_class.new.call

    expect(summary).to have_attributes(checked: 2, changed: 1, linked: 2, fuzzy: 0, unresolved: 0)
    expect(pork.reload).to have_attributes(taxonomy_node: TaxonomyNode.find_by!(name: "pork"), match_type: "exact",
      match_reason: "matched to pork via 'pork'")
    expect(honey.reload.updated_at).to eq(honey.updated_at)
    expect(summary.to_s).to eq("Relinked 2 USDA foods: 1 changed. 2 linked, 0 fuzzy (please check), 0 unresolved")
  end
end
