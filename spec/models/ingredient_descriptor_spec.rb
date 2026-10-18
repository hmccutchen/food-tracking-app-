require "rails_helper"

RSpec.describe IngredientDescriptor do
  subject { described_class.new(word: "spiralized") }

  it { is_expected.to validate_presence_of(:word) }
  it { is_expected.to validate_uniqueness_of(:word).case_insensitive }

  it "normalizes the word" do
    expect(described_class.new(word: "  Thinly  Sliced ").word).to eq("thinly sliced")
  end

  it "refuses words that change or hide what is in the food" do
    [ "breaded", "Fried", "low-sodium", "low sodium", "imitation", "sauce", "spice blend", "honey glazed" ].each do |word|
      descriptor = described_class.new(word:)
      expect(descriptor).not_to be_valid, word
      expect(descriptor.errors[:word].join).to include("can't be a descriptor")
    end
  end

  it "refuses punctuation" do
    expect(described_class.new(word: "diced;")).not_to be_valid
  end

  it "matches on words, so 'extra-virgin' and 'extra virgin' share a key" do
    expect(described_class.key("Extra-Virgin")).to eq("extra virgin")
    described_class.find_or_create_by!(word: "extra-virgin")
    described_class.create!(word: "off", active: false)
    expect(described_class.active_keys).to include("extra virgin")
    expect(described_class.active_keys).not_to include("off")
  end
end
