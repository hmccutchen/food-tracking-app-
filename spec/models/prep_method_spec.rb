require "rails_helper"

RSpec.describe PrepMethod do
  def build_method(**attrs)
    described_class.new({ name: "frying", keywords: %w[fry fried], risk: "Shared fryer oil.",
                          lower_risk_method: "bake", caveat: "still check shared pans" }.merge(attrs))
  end

  it "requires a caveat, a lower-risk method, a risk and a keyword" do
    method = build_method(caveat: " ", lower_risk_method: "", risk: nil, keywords: [ " " ])
    expect(method).not_to be_valid
    expect(method.errors.attribute_names).to include(:caveat, :lower_risk_method, :risk, :keywords)
  end

  it "never lets a note promise anything" do
    method = build_method(lower_risk_method: "#{'sa'}fe to eat")
    expect(method).not_to be_valid
    expect(method.errors[:lower_risk_method].join).to include("risk-free")
  end

  it "reads the lower-risk line with its caveat" do
    expect(build_method.lower_risk_line).to eq("Lower-risk method: bake — still check shared pans")
  end

  it "takes keywords from comma or line separated text, lowercased and de-duplicated" do
    method = build_method(keywords_text: "Fried, fry\nDeep-Fried , fry")
    expect(method.keywords).to eq(%w[fried fry deep-fried])
    expect(method.keywords_text).to eq("fried, fry, deep-fried")
  end

  describe "#detected_in?" do
    let(:method) { build_method(keywords: [ "fry", "deep-fried", "stir fry" ]) }

    it "matches whole words, case-insensitive" do
      expect(method.detected_in?([ "Fry the onions" ])).to be(true)
      expect(method.detected_in?([ "DEEP-FRIED cod" ])).to be(true)
    end

    # Documented behaviour: "fry" does not match "fryer", "fries" or "small-fry".
    # Letters, digits and hyphens are part of a word. Add "fryer" as a keyword
    # if an air fryer should count.
    it "does not match a keyword inside a longer word" do
      expect(method.detected_in?([ "air fryer chicken", "fries", "small-fry" ])).to be(false)
    end

    it "treats spaces and hyphens inside a multi-word keyword alike" do
      expect(method.detected_in?([ "beef stir-fry" ])).to be(true)
      expect(method.detected_in?([ "beef stir  fry" ])).to be(true)
    end

    it "is false with no keywords" do
      expect(build_method(keywords: []).detected_in?([ "fry" ])).to be(false)
    end
  end
end
