require "rails_helper"
require "csv"

RSpec.describe Usda::Importer do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join("spec/fixtures/files/usda") }

  before(:context) { Taxonomy::Seed.load! }
  after(:context) { TaxonomyNode.delete_all }

  def import(path = dir, **options) = described_class.new(path, **options).call

  it "imports only Foundation and SR Legacy rows" do
    import
    expect(Food.count).to eq(26)
    expect(Food.group(:source).count).to eq("foundation" => 11, "sr_legacy" => 15)
    expect(Food.distinct.pluck(:data_type)).to contain_exactly("foundation_food", "sr_legacy_food")
    expect(Food.where("description ILIKE ?", "%SMITHS%")).to be_empty
  end

  it "maps the category, publication date and source" do
    import
    food = Food.find_by!(fdc_id: 170_567)
    expect(food).to have_attributes(description: "Nuts, almonds", source: "sr_legacy", data_type: "sr_legacy_food",
      category: "Nut and Seed Products", publication_date: Date.new(2019, 4, 1))
    expect(food.source_label).to eq("USDA SR Legacy")
  end

  it "keeps the original CSV row verbatim" do
    import
    row = CSV.foreach(dir.join("food.csv"), headers: true).find { |r| r["fdc_id"] == "173757" }.to_h
    expect(Food.find_by!(fdc_id: 173_757).raw).to eq(row)
    expect(row).to include("description" => "Soy sauce made from soy and wheat (shoyu)", "food_category_id" => "16")
  end

  it "leaves ingredients_text nil, since these sources have no ingredient list" do
    import
    expect(Food.where.not(ingredients_text: nil)).to be_empty
  end

  it "links foods to taxonomy nodes and records how" do
    import
    almonds = Food.find_by!(fdc_id: 170_567)
    expect(almonds).to have_attributes(taxonomy_node: TaxonomyNode.find_by!(name: "almond"), match_type: "exact",
      match_reason: "matched to almond via 'almonds'")
    expect(Food.find_by!(fdc_id: 167_763)).to have_attributes(match_type: "fuzzy")
    # Pork became a common food, so the fixture's pork loin now links.
    expect(Food.find_by!(fdc_id: 2_346_370)).to have_attributes(taxonomy_node: TaxonomyNode.find_by!(name: "pork"),
      match_type: "exact")
  end

  it "returns a summary of what it did" do
    summary = import
    expect(summary).to have_attributes(by_source: { "foundation" => 11, "sr_legacy" => 15 }, inserted: 26, updated: 0)
    expect(summary.total).to eq(26)
    expect(summary.skipped).to eq("branded_food" => 2, "sub_sample_food" => 1, "market_acquistion" => 1,
      "agricultural_acquisition" => 1, "survey_fndds_food" => 1)
    expect(summary.links).to eq(linked: 25, fuzzy: 1, unresolved: 0)
    expect(summary.to_s).to include("USDA Foundation: 11", "USDA SR Legacy: 15", "inserted 26, updated 0",
      "Skipped 6 rows", "25 linked, 1 fuzzy (please check), 0 unresolved")
  end

  it "is idempotent and refreshes imported_at on re-run" do
    travel_to(Time.zone.local(2026, 10, 1, 9)) { import }
    almonds = Food.find_by!(fdc_id: 170_567)
    almonds.update_columns(description: "stale")
    created_at = almonds.created_at

    summary = travel_to(Time.zone.local(2026, 10, 15, 9)) { import }

    expect(summary).to have_attributes(inserted: 0, updated: 26)
    expect(Food.count).to eq(26)
    almonds.reload
    expect(almonds.description).to eq("Nuts, almonds")
    expect(almonds.imported_at).to eq(Time.zone.local(2026, 10, 15, 9))
    expect(almonds.created_at).to eq(created_at)
  end

  it "imports only the requested sources" do
    summary = import(sources: %w[foundation])
    expect(Food.distinct.pluck(:source)).to eq(%w[foundation])
    expect(summary.skipped["sr_legacy_food"]).to eq(15)
  end

  it "rejects an unknown source" do
    expect { import(sources: %w[branded]) }.to raise_error(ArgumentError, /unknown USDA source "branded"/)
  end

  it "streams in batches" do
    stub_const("#{described_class}::BATCH_SIZE", 10)
    expect(Food).to receive(:upsert_all).exactly(3).times.and_call_original
    import
    expect(Food.count).to eq(26)
  end

  context "with a folder of unzipped downloads" do
    let(:root) { Pathname(Dir.mktmpdir) }

    after { FileUtils.remove_entry(root) }

    it "imports each subfolder that holds a food.csv" do
      FileUtils.cp_r(dir, root.join("FoodData_Central_sr_legacy_food_csv_2018-04"))
      FileUtils.mkdir(root.join("notes"))
      summary = import(root)
      expect(summary.folders.size).to eq(1)
      expect(Food.count).to eq(26)
    end

    it "explains when there is no food.csv" do
      expect { import(root) }.to raise_error(described_class::MissingFileError, /No food\.csv in/)
    end
  end

  it "explains when the folder is missing" do
    expect { import("/nonexistent/usda") }
      .to raise_error(described_class::MissingFileError, "USDA folder not found: /nonexistent/usda")
  end
end
