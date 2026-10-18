require "rails_helper"

RSpec.describe Evaluation::Tier do
  let(:ordered) { [ described_class::CONFLICT, described_class::POSSIBLE_CONFLICT, described_class::UNKNOWN, described_class::NONE ] }

  it "orders conflict > possible_conflict > unknown > none" do
    expect(ordered.each_cons(2)).to all(satisfy { |worse, milder| worse > milder })
    expect(ordered.shuffle(random: Random.new(1)).sort.reverse).to eq(ordered)
  end

  it "names the tiers with symbols only" do
    expect(ordered.map(&:to_sym)).to eq(%i[conflict possible_conflict unknown none])
    expect(described_class::CONFLICT.to_s).to eq("conflict")
  end

  it "exposes no numbers" do
    expect(described_class::CONFLICT).not_to respond_to(:severity)
    expect(described_class::CONFLICT).not_to respond_to(:to_i)
  end

  it "cannot be constructed outside the four constants" do
    expect { described_class.new(:fine, 9) }.to raise_error(NoMethodError)
  end

  describe ".worst" do
    it "returns the worst tier given" do
      expect(described_class.worst(described_class::UNKNOWN, described_class::CONFLICT, described_class::NONE))
        .to eq(described_class::CONFLICT)
    end

    it "accepts names and arrays" do
      expect(described_class.worst([ :unknown, "possible_conflict" ])).to eq(described_class::POSSIBLE_CONFLICT)
    end

    it "is NONE with no tiers" do
      expect(described_class.worst).to eq(described_class::NONE)
      expect(described_class.worst([])).to be_none
    end
  end

  describe ".fetch" do
    it "rejects unknown names" do
      expect { described_class.fetch(:fine) }.to raise_error(ArgumentError)
    end

    it "returns the same object for a name" do
      expect(described_class[:conflict]).to equal(described_class::CONFLICT)
    end
  end
end
