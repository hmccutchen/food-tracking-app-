require "rails_helper"

RSpec.describe "Evaluation result serialization" do
  let(:ann) { create(:patient) }
  let(:ben) { create(:patient) }
  let(:conflict) do
    Evaluation::Flag.new(tier: :conflict, ingredient: "peanut butter", source: :allergy,
      reason: "peanut butter is a peanut (allergy)")
  end
  let(:marked_ok) do
    Evaluation::Flag.new(tier: :possible_conflict, ingredient: "soy sauce", source: :condition,
      reason: "soy sauce is high in sodium (low sodium)").override
  end
  let(:unknown) { Evaluation::Flag.new(tier: :unknown, ingredient: "zzqx", source: :unresolved, reason: "'zzqx' not recognized") }

  let(:result) do
    Evaluation::GroupResult.new(
      ingredients: [ "peanut butter", "soy sauce", "zzqx" ],
      patient_results: [
        Evaluation::PatientResult.new(patient_id: ann.id, profile_version: ann.profile_version, flags: [ conflict, marked_ok ]),
        Evaluation::PatientResult.new(patient_id: ben.id, profile_version: ben.profile_version, flags: [ unknown ])
      ],
      missing_patient_ids: [ 999_999 ],
      evaluated_at: Time.zone.local(2026, 10, 18, 9, 30, 15.123456r)
    )
  end

  def round_trip(value) = value.class.from_h(JSON.parse(value.to_h.to_json))

  it "round-trips a GroupResult through JSON with tiers, reasons, overrides and stamps intact" do
    copy = round_trip(result)

    expect(copy).to eq(result)
    expect(copy.tier).to eq(Evaluation::Tier::CONFLICT)
    expect(copy.for_patient(ann.id).overridden_flags.sole.override_reason).to eq("you marked this OK")
    expect(copy.for_patient(ben.id).tier).to eq(Evaluation::Tier::UNKNOWN)
    expect(copy.profile_versions).to eq(ann.id => ann.profile_version, ben.id => ben.profile_version)
    expect(copy.missing_patient_ids).to eq([ 999_999 ])
    expect(copy.evaluated_at).to eq(result.evaluated_at)
  end

  it "round-trips flags and patient results on their own" do
    expect(round_trip(conflict)).to eq(conflict)
    expect(round_trip(marked_ok)).to eq(marked_ok)
    patient_result = result.patient_results.first
    expect(round_trip(patient_result)).to eq(patient_result)
    expect(Evaluation::Tier.fetch(Evaluation::Tier::POSSIBLE_CONFLICT.as_json)).to eq(Evaluation::Tier::POSSIBLE_CONFLICT)
  end

  it "stores tier names only, never numbers" do
    json = result.to_h.to_json
    expect(json).to include('"tier":"conflict"', '"tier":"possible_conflict"')
    expect(JSON.parse(json).keys).to contain_exactly("patient_results", "ingredients", "profile_versions",
      "missing_patient_ids", "evaluated_at")
  end

  it "keeps a nil ingredient list nil" do
    empty = Evaluation::GroupResult.new(patient_results: [], ingredients: nil)
    expect(round_trip(empty).ingredients).to be_nil
    expect(round_trip(empty).tier).to eq(Evaluation::Tier::UNKNOWN)
  end

  it "reports a stored result stale after the profile changes or the patient is deleted" do
    copy = Evaluation::GroupResult.from_h(JSON.parse(result.to_h.except("missing_patient_ids").to_json))
    expect(copy).not_to be_stale

    ann.restrictions.create!(kind: :allergy, term: "milk")
    expect(copy).to be_stale

    fresh = Evaluation::GroupResult.from_h(JSON.parse(result.to_h.merge("missing_patient_ids" => [],
      "profile_versions" => { ben.id.to_s => ben.profile_version }).to_json))
    expect(fresh).not_to be_stale
    ben.destroy!
    expect(fresh).to be_stale
  end
end
