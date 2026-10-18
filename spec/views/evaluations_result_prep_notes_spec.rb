require "rails_helper"

RSpec.describe "evaluations/_result with prep notes" do
  let(:patient) { create(:patient, display_name: "Ana Ruiz") }
  let(:result) do
    Evaluation::GroupResult.new(ingredients: [ "x" ],
      patient_results: [ Evaluation::PatientResult.new(patient_id: patient.id, profile_version: patient.profile_version) ])
  end
  let(:note) do
    PrepNotes::Note.new(key: "prep-1-abc", method_name: "frying", risk: "Fryer oil is often shared.",
      terms: [ "shellfish" ], lower_risk_line: "Lower-risk method: bake — still check shared pans")
  end

  it "renders advisory notes and the cross-contact line without touching the tier" do
    render partial: "evaluations/result", locals: { result:, patients: {}, prep_notes: [ note ],
                                                    cross_contact: "Check shared pans, oil, and cutting boards" }
    expect(rendered).to include("Preparation note (advisory)", "frying", "Fryer oil is often shared.",
      "Relevant to: shellfish", "Lower-risk method: bake — still check shared pans",
      'data-dismiss-key-value="prep-1-abc"', "Check shared pans, oil, and cutting boards")
    expect(rendered).to include('data-tier="none"')
  end

  it "stays backward compatible when no notes are passed" do
    render partial: "evaluations/result", locals: { result:, patients: {} }
    expect(rendered).not_to include("Preparation note", "cross-contact")
  end
end
