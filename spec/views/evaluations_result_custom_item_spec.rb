require "rails_helper"

RSpec.describe "evaluations/_result custom item links" do
  let(:patient) { create(:patient) }
  let(:unknown) do
    Evaluation::Flag.new(tier: :unknown, ingredient: "Mrs. P's soup", source: :unresolved,
      reason: "'Mrs. P's soup' not recognized")
  end
  let(:missing) { Evaluation::Flag.new(tier: :unknown, reason: "no ingredient list found", source: :missing_list) }
  let(:conflict) { Evaluation::Flag.new(tier: :conflict, ingredient: "peanut", source: :allergy, reason: "peanut is listed (allergy)") }

  def result(flags)
    Evaluation::GroupResult.new(ingredients: [ "x" ], profile_versions: nil,
      patient_results: [ Evaluation::PatientResult.new(patient_id: patient.id, profile_version: patient.profile_version, flags:) ])
  end

  it "links each unresolved UNKNOWN flag to a prefilled custom item form, breaking out of frames" do
    render partial: "evaluations/result", locals: { result: result([ unknown, conflict ]) }
    link = Capybara.string(rendered).find_link("Add as custom item")
    expect(link[:href]).to eq(new_custom_item_path(name: "Mrs. P's soup"))
    expect(link["data-turbo-frame"]).to eq("_top")
    expect(Capybara.string(rendered)).to have_link("Add as custom item", count: 1)
  end

  it "adds no link for other unknowns, or when turned off" do
    render partial: "evaluations/result", locals: { result: result([ missing ]) }
    expect(rendered).not_to include("Add as custom item")
    render partial: "evaluations/result", locals: { result: result([ unknown ]), custom_item_links: false }
    expect(rendered).not_to include("Add as custom item")
  end
end
