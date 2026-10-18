require "rails_helper"

RSpec.describe MealSuggester::Prompt do
  subject(:prompt) do
    described_class.new(
      terms: [ "milk", "peanut", "sodium" ],
      request: "  Warm dinner for Ann Lee, something soft.  Ann's son visits. ",
      rejected: [ "butter", "milk" ],
      redact: [ "Ann Lee" ]
    )
  end

  it "renders the provider-neutral prompt" do
    expect(prompt.text).to eq(<<~TEXT)
      Suggest 3 different meals for this request: Warm dinner for the patient, something soft. the patient's son visits.

      Leave these out entirely. Do not use them, or any ingredient that contains them or is made from them:
      - milk
      - peanut
      - sodium

      An earlier suggestion was dropped because it used these. Do not use them either:
      - butter

      Reply with JSON only, no other text, in exactly this shape:
      {"meals":[{"dish":"...","ingredients":["..."],"prep_notes":["..."]}]}

      - "dish" is the meal's name.
      - "ingredients" lists every ingredient, one per array element. Name each one specifically, for example "low-sodium soy sauce", not "sauce".
      - "prep_notes" are short preparation tips. Use [] if there are none.
    TEXT
  end

  it "never contains a patient name" do
    expect(prompt.text).not_to match(/\bann\b|\blee\b/i)
  end

  it "makes no promise about suitability" do
    expect(prompt.text).not_to match(/\b(safe|safety|guarantee|allerg\w*|patient's (diet|needs))\b/i)
  end

  it "leaves out empty sections and clamps the count" do
    text = described_class.new(terms: [], request: "", count: 9).text
    expect(text).to start_with("Suggest 5 different meals.\n\nReply with JSON only")
    expect(text).not_to include("Leave these out", "earlier suggestion")
    expect(described_class.new(terms: [], request: "lunch", count: 1).text).to start_with("Suggest 1 meal for this request: lunch\n")
  end

  it "asks for the JSON shape as structured output" do
    meal = prompt.schema.dig(:schema, :properties, :meals, :items)
    expect(meal[:required]).to eq(%w[dish ingredients prep_notes])
    expect(meal.dig(:properties, :ingredients)).to eq(type: "array", items: { type: "string" })
  end
end
