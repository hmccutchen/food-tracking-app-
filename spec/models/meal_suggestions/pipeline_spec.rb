require "rails_helper"

RSpec.describe MealSuggestions::Pipeline do
  before(:context) { load_prep_method_seed! }
  after(:context) { clear_prep_method_seed! }

  let(:user) { create(:user) }
  let(:ann) { create(:patient, user:, display_name: "Ann Lee") }
  let(:bertram) { create(:patient, user:, display_name: "Bertram") }
  let(:credential) { adapter_credential("openai") }

  let(:peanut_toast) { FakeMealAdapter.meal("Peanut toast", "peanut butter", "toast") }
  let(:shrimp_rice) { FakeMealAdapter.meal("Shrimp rice", "shrimp", "rice") }
  let(:lentil_soup) { FakeMealAdapter.meal("Lentil soup", "red lentils", "carrot", "curry paste") }
  let(:soy_noodles) { FakeMealAdapter.meal("Soy noodles", "rice noodles", "soy sauce") }

  before do
    ann.restrictions.create!(kind: :allergy, term: "peanut")
    bertram.restrictions.create!(kind: :allergy, term: "shellfish")
    bertram.restrictions.create!(kind: :condition, term: "low sodium")
  end

  def run(*replies, patients: [ ann, bertram ], request: "Dinner for Ann Lee and Bertram", **)
    adapter = FakeMealAdapter.new(*replies)
    [ described_class.new(credential:, patients:, request:, adapter:, **).call, adapter ]
  end

  def meals(*list) = FakeMealAdapter.meals(*list)
  def dishes(entries) = entries.map { |entry| entry.suggestion.dish }

  it "drops conflicts and keeps the rest with their group result" do
    outcome, adapter = run(meals(peanut_toast, lentil_soup, soy_noodles))

    expect(adapter.calls).to eq(1)
    expect(outcome).to be_found
    expect(dishes(outcome.kept)).to eq([ "Lentil soup", "Soy noodles" ])
    expect(outcome.kept.map { |kept| kept.group_result.tier.to_sym }).to eq(%i[unknown possible_conflict])
    expect(dishes(outcome.dropped)).to eq([ "Peanut toast" ])
    expect(outcome.dropped.sole.blocking_ingredients).to eq([ "peanut butter" ])
    expect(outcome.dropped.sole.reasons).to all(match(/peanut/))
    expect(outcome.attempts.sole).to have_attributes(number: 1, status: :ok, rejected_sent: [], meals_returned: 3,
      meals_dropped: 1, error_class: nil)
    expect(outcome.final_error).to be_nil
    expect(outcome.profile_versions).to eq(ann.reload.profile_stamp.merge(bertram.reload.profile_stamp))
  end

  it "retries with a growing rejected list and stops on the first attempt that keeps a meal" do
    outcome, adapter = run(meals(peanut_toast), meals(shrimp_rice), meals(lentil_soup), meals(soy_noodles))

    expect(adapter.calls).to eq(3)
    expect(outcome.attempts.map(&:rejected_sent)).to eq([ [], [ "peanut butter" ], [ "peanut butter", "shrimp" ] ])
    expect(adapter.prompts.map(&:rejected)).to eq([ [], [ "peanut butter" ], [ "peanut butter", "shrimp" ] ])
    expect(adapter.prompts.last.text).to include("- peanut butter\n- shrimp")
    expect(dishes(outcome.kept)).to eq([ "Lentil soup" ])
    expect(dishes(outcome.dropped)).to eq([ "Peanut toast", "Shrimp rice" ])
  end

  it "stops after the first attempt when it keeps a meal" do
    outcome, adapter = run(meals(lentil_soup), meals(peanut_toast))
    expect(adapter.calls).to eq(1)
    expect(outcome.attempts.size).to eq(1)
  end

  it "makes at most three attempts, then reports what blocked every meal" do
    outcome, adapter = run(meals(peanut_toast, shrimp_rice))

    expect(adapter.calls).to eq(3)
    expect(outcome).not_to be_found
    expect(outcome.final_error).to be_nil
    expect(outcome.dropped.size).to eq(6)
    expect(outcome.attempts.map(&:meals_dropped)).to eq([ 2, 2, 2 ])
    expect(outcome.blocking_conflicts).to eq(outcome.blocking_conflicts.uniq)
    expect(outcome.blocking_conflicts).to include(match(/peanut butter.*peanut \(allergy\)/), match(/shrimp.*shellfish/))
  end

  it "honours a smaller retry budget" do
    _outcome, adapter = run(meals(peanut_toast), max_retries: 0)
    expect(adapter.calls).to eq(1)
  end

  it "counts a malformed reply as a failed attempt and retries" do
    outcome, adapter = run("Sorry, I can't help with that.", meals(lentil_soup))

    expect(adapter.calls).to eq(2)
    expect(outcome.attempts.map(&:status)).to eq(%i[malformed ok])
    expect(outcome.attempts.first).to have_attributes(error_class: "Ai::MalformedResponseError", meals_returned: 0,
      error_message: "OpenAI sent back something we couldn't read. Trying again may help.")
    expect(dishes(outcome.kept)).to eq([ "Lentil soup" ])
    expect(outcome.final_error).to be_nil
  end

  it "sets final_error when the last attempt failed and nothing was kept" do
    outcome, adapter = run("not json")
    expect(adapter.calls).to eq(3)
    expect(outcome).not_to be_found
    expect(outcome.final_error).to be_a(Ai::MalformedResponseError)
  end

  [ Ai::RateLimitError, Ai::TimeoutError, Ai::ProviderError ].each do |error|
    it "retries after #{error.name} within the same budget" do
      outcome, adapter = run(error, error, meals(lentil_soup))
      expect(adapter.calls).to eq(3)
      expect(outcome.attempts.map(&:status)).to eq(%i[error error ok])
      expect(outcome).to be_found
    end
  end

  [ Ai::InvalidKeyError, Ai::QuotaExceededError, Ai::ModelMissingError ].each do |error|
    it "stops at once on #{error.name}" do
      outcome, adapter = run(error, meals(lentil_soup))
      expect(adapter.calls).to eq(1)
      expect(outcome.final_error).to be_a(error)
      expect(outcome.attempts.sole).to have_attributes(status: :error, error_class: error.name,
        error_message: error.new("openai").plain_message)
      expect(outcome).not_to be_found
    end
  end

  it "keeps the rejected list from earlier attempts across an error" do
    _outcome, adapter = run(meals(peanut_toast), Ai::TimeoutError, meals(lentil_soup))
    expect(adapter.prompts.map(&:rejected)).to eq([ [], [ "peanut butter" ], [ "peanut butter" ] ])
  end

  it "never lets AI output touch the tier" do
    sneaky = meals(
      peanut_toast.merge("tier" => "safe", "allergen_free" => true, "flags" => []),
      soy_noodles.merge("tier" => "none", "safe" => true)
    )
    outcome, = run(sneaky)
    plain, = run(meals(peanut_toast, soy_noodles))

    expect(dishes(outcome.dropped)).to eq([ "Peanut toast" ])
    expect(outcome.dropped.sole.group_result.tier).to eq(Evaluation::Tier::CONFLICT)
    expect(outcome.kept.sole.group_result.tier).to eq(Evaluation::Tier::POSSIBLE_CONFLICT)
    flags = ->(o) { (o.kept + o.dropped).map { |entry| entry.group_result.patient_results.map(&:flags) } }
    expect(flags.call(outcome)).to eq(flags.call(plain))
    expect(outcome.kept.sole.suggestion.to_h.keys).to eq(%i[dish ingredients prep_notes])
  end

  it "never sends patient names" do
    ann.restrictions.create!(kind: :cannot, term: "Bertram's mushrooms")
    _outcome, adapter = run(meals(peanut_toast), meals(lentil_soup))

    texts = adapter.prompts.map(&:text)
    expect(texts.size).to eq(2)
    texts.each { |text| expect(text).not_to match(/ann|lee|bertram/i) }
    expect(texts.first).to include("Dinner for the patient and the patient")
  end

  it "attaches prep notes and the cross-contact line to kept meals" do
    fried = FakeMealAdapter.meal("Fried rice", "rice", "egg", prep_notes: [ "deep-fry the rice" ])
    outcome, = run(meals(fried))

    kept = outcome.kept.sole
    expect(kept.prep_notes.map(&:method_name)).to include("frying")
    expect(kept.cross_contact).to eq(PrepNotes::CROSS_CONTACT_LINE)
  end

  it "leaves the cross-contact line off when nobody has an allergy" do
    patient = create(:patient, user:)
    patient.restrictions.create!(kind: :condition, term: "low sodium")
    outcome, = run(meals(lentil_soup), patients: [ patient ])
    expect(outcome.kept.sole.cross_contact).to be_nil
  end
end
