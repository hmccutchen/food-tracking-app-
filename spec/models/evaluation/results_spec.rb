require "rails_helper"

RSpec.describe "Evaluation results" do
  def flag(tier, overridden: false)
    Evaluation::Flag.new(tier:, ingredient: "x", reason: "reason for #{tier}", source: :condition, overridden:)
  end

  def patient_result(id, *tiers)
    Evaluation::PatientResult.new(patient_id: id, profile_version: 1, flags: tiers.map { |tier| flag(tier) })
  end

  def group(*patient_results)
    Evaluation::GroupResult.new(patient_results:, ingredients: [ "x" ], evaluated_at: Time.current)
  end

  describe Evaluation::PatientResult do
    it "is NONE with no flags" do
      result = described_class.new(patient_id: 1, profile_version: 1, flags: [])
      expect(result.tier).to eq(Evaluation::Tier::NONE)
      expect(result).to be_no_flags
    end

    it "takes the worst unoverridden flag" do
      result = described_class.new(patient_id: 1, profile_version: 1,
        flags: [ flag(:unknown), flag(:conflict, overridden: true), flag(:possible_conflict) ])
      expect(result.tier).to eq(Evaluation::Tier::POSSIBLE_CONFLICT)
      expect(result.active_flags.map(&:tier)).to eq([ Evaluation::Tier::UNKNOWN, Evaluation::Tier::POSSIBLE_CONFLICT ])
      expect(result.overridden_flags.map(&:tier)).to eq([ Evaluation::Tier::CONFLICT ])
    end

    it "drops exact duplicate flags only" do
      result = described_class.new(patient_id: 1, profile_version: 1, flags: [ flag(:unknown), flag(:unknown), flag(:conflict) ])
      expect(result.flags.size).to eq(2)
    end

    it "carries no patient name" do
      expect(described_class.members).to eq(%i[patient_id profile_version flags])
    end
  end

  describe Evaluation::GroupResult do
    it "takes the worst patient: conflict + possible + none is conflict" do
      result = group(patient_result(1, :conflict), patient_result(2, :possible_conflict), patient_result(3))
      expect(result.tier).to eq(Evaluation::Tier::CONFLICT)
    end

    it "is never softer than any patient over many random combinations" do
      random = Random.new(20_261_017)
      tiers = Evaluation::Tier::ALL.map(&:to_sym) - [ :none ]

      500.times do
        patients = Array.new(random.rand(1..6)) do |index|
          patient_result(index + 1, *Array.new(random.rand(0..4)) { tiers.sample(random:) })
        end
        result = group(*patients)

        expect(result.tier).to eq(patients.map(&:tier).max)
        expect(patients).to all(satisfy { |patient| result.tier >= patient.tier })
      end
    end

    it "is UNKNOWN with no patients: checking against nobody proves nothing" do
      expect(group.tier).to eq(Evaluation::Tier::UNKNOWN)
    end

    it "says no flags found, never a guarantee, when there are none" do
      result = group(patient_result(1), patient_result(2))
      expect(result.summary).to eq("No flags found — this isn't a guarantee")
      expect(result).to be_no_flags
    end

    it "gives a non-reassuring summary for every other tier" do
      %i[conflict possible_conflict unknown].each do |tier|
        summary = group(patient_result(1, tier)).summary
        expect(summary).not_to eq("No flags found — this isn't a guarantee")
        expect(summary).not_to match(/\bsafe\b/i)
      end
    end

    it "collects active conflicts and their ingredients across patients" do
      conflict = Evaluation::Flag.new(tier: :conflict, ingredient: "almond", reason: "r", source: :allergy)
      other = Evaluation::Flag.new(tier: :conflict, ingredient: "shrimp", reason: "r2", source: :cannot)
      cleared = Evaluation::Flag.new(tier: :conflict, ingredient: "milk", reason: "r3", source: :allergy, overridden: true)
      result = group(
        Evaluation::PatientResult.new(patient_id: 1, profile_version: 1, flags: [ conflict, flag(:unknown) ]),
        Evaluation::PatientResult.new(patient_id: 2, profile_version: 1, flags: [ other, conflict, cleared ])
      )
      expect(result.conflicts).to eq([ conflict, other, conflict ])
      expect(result.blocking_ingredients).to eq(%w[almond shrimp])
    end

    it "derives profile_versions from the patient results by default" do
      result = Evaluation::GroupResult.new(patient_results: [ patient_result(7) ], ingredients: [])
      expect(result.profile_versions).to eq(7 => 1)
    end
  end
end

RSpec.describe Evaluation::GroupResult, "with no patients" do
  it "is unknown, never no flags, and says nothing was checked" do
    result = Evaluation::Engine.new([]).evaluate([ "almond flour" ])

    expect(result.tier).to eq(Evaluation::Tier::UNKNOWN)
    expect(result).not_to be_no_flags
    expect(result.summary).to eq("No patients selected — nothing was checked")
  end
end
