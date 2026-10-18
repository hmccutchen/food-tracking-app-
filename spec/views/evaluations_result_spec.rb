require "rails_helper"

RSpec.describe "evaluations/_result" do
  let(:conflict) { Evaluation::Flag.new(tier: :conflict, ingredient: "peanut", source: :allergy, reason: "peanut is listed (allergy)") }
  let(:cleared) do
    Evaluation::Flag.new(tier: :possible_conflict, ingredient: "soy sauce", source: :condition,
      reason: "soy sauce is high in sodium (low sodium)").override
  end

  def result_for(patient, flags, versions: nil)
    Evaluation::GroupResult.new(ingredients: [ "x" ], profile_versions: versions,
      patient_results: [ Evaluation::PatientResult.new(patient_id: patient.id, profile_version: patient.profile_version, flags:) ])
  end

  it "labels tiers in words with a data-tier hook and keeps overridden flags visible" do
    patient = create(:patient, display_name: "Ana Ruiz")
    render partial: "evaluations/result", locals: { result: result_for(patient, [ conflict, cleared ]), patients: { patient.id => "Ana Ruiz" } }
    expect(rendered).to include('data-tier="conflict"', "Conflict: peanut is listed (allergy)", "Ana Ruiz")
    expect(rendered).to include("You marked this OK", "soy sauce is high in sodium (low sodium)")
    expect(rendered).not_to include("Out of date")
  end

  it "says no flags found, never a guarantee, when nothing is flagged" do
    patient = create(:patient)
    render partial: "evaluations/result", locals: { result: result_for(patient, []), patients: { patient.id => patient } }
    expect(rendered).to include("No flags found — this isn&#39;t a guarantee", patient.display_name)
  end

  it "marks a stale result out of date" do
    patient = create(:patient)
    result = result_for(patient, [ conflict ], versions: { patient.id => patient.profile_version })
    patient.update!(notes: "changed")
    render partial: "evaluations/result", locals: { result:, patients: {} }
    expect(rendered).to include("Out of date — re-check", "Patient no longer on file")
  end
end
