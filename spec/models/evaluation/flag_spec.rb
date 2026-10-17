require "rails_helper"

RSpec.describe Evaluation::Flag do
  let(:attrs) { { tier: :conflict, ingredient: "almond", reason: "almond is a tree nut (allergy)", source: :allergy } }

  it "defaults to not overridden" do
    flag = described_class.new(**attrs)
    expect(flag).to have_attributes(tier: Evaluation::Tier::CONFLICT, overridden: false, override_reason: nil)
    expect(flag).to be_active
  end

  [ nil, "", "   " ].each do |blank|
    it "requires a reason (#{blank.inspect})" do
      expect { described_class.new(**attrs, reason: blank) }.to raise_error(ArgumentError, /reason/)
    end
  end

  it "rejects an unknown source" do
    expect { described_class.new(**attrs, source: :ai) }.to raise_error(ArgumentError, /source/)
  end

  it "rejects an unknown tier" do
    expect { described_class.new(**attrs, tier: :fine) }.to raise_error(ArgumentError, /tier/)
  end

  it "accepts every documented source" do
    %i[allergy intolerance condition cannot fuzzy ambiguous unresolved missing_list].each do |source|
      expect(described_class.new(**attrs, source:).source).to eq(source)
    end
  end

  it "keeps the finding when overridden" do
    flag = described_class.new(**attrs).override
    expect(flag).to have_attributes(overridden: true, override_reason: "you marked this OK",
      reason: "almond is a tree nut (allergy)")
  end

  it "is a value: equal flags compare equal" do
    expect(described_class.new(**attrs)).to eq(described_class.new(**attrs))
    expect([ described_class.new(**attrs), described_class.new(**attrs) ].uniq.size).to eq(1)
  end
end
