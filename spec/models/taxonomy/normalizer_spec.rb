require "rails_helper"

RSpec.describe Taxonomy::Normalizer do
  describe ".call" do
    {
      "  Tree   Nuts " => "tree nuts",
      "ALMOND FLOUR" => "almond flour",
      "no nuts" => "nuts",
      "No Nuts!" => "nuts",
      "without dairy" => "dairy",
      "free of sesame" => "sesame",
      "avoid shellfish" => "shellfish",
      "nut-free" => "nut",
      "gluten free" => "gluten",
      "no soy-free" => "soy",
      "cow's milk" => "cow's milk",
      "cow’s milk" => "cow's milk",
      "all-purpose flour" => "all-purpose flour",
      "'quoted' -dashed- (parens), commas; etc." => "quoted dashed parens commas etc",
      "fish/shellfish" => "fish shellfish"
    }.each do |input, expected|
      it "normalizes #{input.inspect} to #{expected.inspect}" do
        expect(described_class.call(input)).to eq(expected)
      end
    end

    it "returns an empty string for nil and blank input" do
      expect(described_class.call(nil)).to eq("")
      expect(described_class.call("   ")).to eq("")
    end

    it "does not strip words that merely start like a negation" do
      expect(described_class.call("nougat")).to eq("nougat")
      expect(described_class.call("avocado")).to eq("avocado")
      expect(described_class.call("freekeh")).to eq("freekeh")
    end
  end

  describe ".singularize" do
    {
      "almonds" => "almond",
      "tree nuts" => "tree nut",
      "anchovies" => "anchovy",
      "radishes" => "radish",
      "peaches" => "peach",
      "boxes" => "box",
      "cheeses" => "cheese",
      "spices" => "spice"
    }.each do |plural, singular|
      it "turns #{plural.inspect} into #{singular.inspect}" do
        expect(described_class.singularize(plural)).to eq(singular)
      end
    end

    %w[glass hummus couscous asparagus nut egg gas ss].each do |word|
      it "leaves #{word.inspect} alone" do
        expect(described_class.singularize(word)).to be_nil
      end
    end
  end

  describe ".candidates" do
    it "includes the term and its singular form" do
      expect(described_class.candidates("almonds")).to eq(%w[almonds almond])
    end

    it "includes only the term when it is not plural" do
      expect(described_class.candidates("almond")).to eq(%w[almond])
    end
  end
end
