require "rails_helper"

RSpec.describe Food do
  describe "validations" do
    subject { build(:food) }

    it { is_expected.to validate_presence_of(:description) }
    it { is_expected.to validate_uniqueness_of(:fdc_id) }
    it { is_expected.to validate_inclusion_of(:match_type).in_array(described_class::MATCH_TYPES) }
  end

  it "labels its source" do
    expect(build(:food, source: "foundation").source_label).to eq("USDA Foundation")
    expect(build(:food, source: "sr_legacy").source_label).to eq("USDA SR Legacy")
  end

  describe ".search" do
    before do
      [ "Nuts, almonds", "Beverages, almond milk, unsweetened, shelf stable", "Cheese, cheddar",
        "Cheese, cottage, creamed, large or small curd", "Soy sauce made from soy and wheat (shoyu)",
        "Bananas, raw", "Oil, sesame, salad or cooking" ].each { |description| create(:food, description:) }
    end

    def search(query) = described_class.search(query).map(&:description)

    it "tolerates typos" do
      expect(search("almnd")).to include("Nuts, almonds")
      expect(search("chedar").first).to eq("Cheese, cheddar")
      expect(search("banan")).to eq([ "Bananas, raw" ])
    end

    it "orders the closest match first" do
      expect(search("almonds").first).to eq("Nuts, almonds")
      expect(search("almond milk").first).to eq("Beverages, almond milk, unsweetened, shelf stable")
      expect(search("almnd").first(2)).to eq([ "Nuts, almonds", "Beverages, almond milk, unsweetened, shelf stable" ])
    end

    it "normalizes the query" do
      expect(search("  ALMONDS!! ")).to start_with("Nuts, almonds")
      expect(search("soy-sauce")).to start_with("Soy sauce made from soy and wheat (shoyu)")
    end

    it "finds nothing for gibberish or a blank query" do
      expect(search("zzqxv")).to be_empty
      expect(search("  ")).to be_empty
      expect(search(nil)).to be_empty
    end

    it "treats LIKE wildcards literally" do
      expect(search("%")).to be_empty
      expect(search("_")).to be_empty
    end

    it "returns at most 25 results" do
      30.times { |n| create(:food, description: "Cheese, cheddar, sharp, batch #{n}") }
      expect(described_class.search("cheddar").size).to eq(25)
      expect(described_class.search("cheddar", limit: 5).size).to eq(5)
    end
  end
end
