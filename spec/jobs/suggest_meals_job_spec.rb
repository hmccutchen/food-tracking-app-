require "rails_helper"

RSpec.describe SuggestMealsJob do
  include ActiveJob::TestHelper

  before(:context) { load_prep_method_seed! }
  after(:context) { clear_prep_method_seed! }

  let(:user) { create(:user, active_provider: "openai") }
  let!(:credential) { create(:provider_credential, user:, provider: "openai", model: "model-a") }
  let(:ann) { create(:patient, user:, display_name: "Ann Lee") }
  let(:bertram) { create(:patient, user:, display_name: "Bertram") }
  let(:meal_request) do
    create(:meal_request, user:, patient_ids: [ ann.id, bertram.id ], request_text: "Soft dinner for Ann Lee and Bertram")
  end

  let(:peanut_toast) { FakeMealAdapter.meal("Peanut toast", "peanut butter", "toast") }
  let(:lentil_soup) { FakeMealAdapter.meal("Lentil soup", "red lentils", "carrot", prep_notes: [ "simmer until soft" ]) }

  before do
    ann.restrictions.create!(kind: :allergy, term: "peanut")
    bertram.restrictions.create!(kind: :condition, term: "low sodium")
  end

  after { described_class.adapter_factory = nil }

  def with_adapter(*replies)
    adapter = FakeMealAdapter.new(*replies)
    described_class.adapter_factory = ->(_credential) { adapter }
    adapter
  end

  def run_job(request = meal_request)
    described_class.perform_now(user.id, request.id)
    request.reload
  end

  def stream_for(request) = Turbo::StreamsChannel.send(:stream_name_from, request)

  it "stores kept and dropped meals with the engine's tiers and reasons" do
    adapter = with_adapter(FakeMealAdapter.meals(peanut_toast, lentil_soup))

    expect { run_job }.to have_broadcasted_to(stream_for(meal_request)).at_least(:twice)

    expect(meal_request).to be_found
    expect(meal_request).to have_attributes(attempts_count: 1, provider: "openai", error_message: nil)
    expect(meal_request.profile_versions).to eq(ann.id.to_s => ann.reload.profile_version,
      bertram.id.to_s => bertram.reload.profile_version)
    kept = meal_request.kept_suggestions.sole
    expect(kept).to have_attributes(dish: "Lentil soup", ingredients: [ "red lentils", "carrot" ],
      prep_notes: [ "simmer until soft" ], position: 0)
    expect(kept.tier).to eq(kept.group_result.tier.to_s)
    expect(kept.group_result.for_patient(ann.id)).to be_present
    dropped = meal_request.dropped_suggestions.sole
    expect(dropped).to have_attributes(dish: "Peanut toast", tier: "conflict", position: 1)
    expect(dropped.blocking_reasons).to include(match(/peanut butter.*peanut \(allergy\)/))
    expect(adapter.calls).to eq(1)
  end

  it "encrypts the stored result" do
    with_adapter(FakeMealAdapter.meals(peanut_toast, lentil_soup))
    run_job
    raw = MealSuggestion.connection.select_values("SELECT result_json FROM meal_suggestions")
    expect(raw).to all(satisfy { |value| !value.include?("peanut") && !value.include?("sodium") })
  end

  it "never sends patient names to the provider" do
    adapter = with_adapter(FakeMealAdapter.meals(lentil_soup))
    run_job
    text = adapter.prompts.map(&:text).join("\n")
    expect(text).not_to include("Ann Lee")
    expect(text).not_to include("Bertram")
    expect(text).to include("peanut")
  end

  it "reports not found with what blocked every meal" do
    adapter = with_adapter(FakeMealAdapter.meals(peanut_toast))
    run_job

    expect(meal_request).to be_not_found
    expect(meal_request.attempts_count).to eq(3)
    expect(adapter.calls).to eq(3)
    expect(meal_request.blocking_conflicts).to include(match(/peanut butter.*peanut \(allergy\)/))
    expect(meal_request.dropped_suggestions.size).to eq(3)
    expect(meal_request.kept_suggestions).to be_empty
    raw = MealRequest.connection.select_value("SELECT blocking_conflicts FROM meal_requests")
    expect(raw).not_to include("peanut")
  end

  Ai::Error.classes.each do |klass|
    it "fails with the plain message for #{klass.name}" do
      with_adapter(klass)
      run_job

      expect(meal_request).to be_failed
      expect(meal_request.error_message).to eq(klass.new("openai").plain_message)
      expect(meal_request.error_code).to eq(klass.code)
      expect(meal_request.error_message).not_to include(klass.name, credential.api_key)
      expect(meal_request.attempts_count).to be_between(1, 3)
    end
  end

  it "fails with a link-to-settings message when no provider is set up" do
    user.update!(active_provider: nil)
    run_job
    expect(meal_request).to be_failed
    expect(meal_request.error_message).to eq(described_class::NO_PROVIDER)
    expect(meal_request).to be_settings_error
  end

  it "fails without calling the provider when no model is picked" do
    credential.update!(model: nil)
    adapter = with_adapter(FakeMealAdapter.meals(lentil_soup))
    run_job
    expect(meal_request).to be_failed
    expect(meal_request.error_message).to eq("Pick a model for OpenAI in AI settings.")
    expect(meal_request).to be_settings_error
    expect(adapter.calls).to eq(0)
  end

  it "fails when none of the patients are on file any more" do
    meal_request
    ann.destroy!
    bertram.destroy!
    run_job
    expect(meal_request).to be_failed
    expect(meal_request.error_message).to eq(described_class::NO_PATIENTS)
  end

  it "takes ids only as arguments" do
    expect { described_class.perform_later(user.id, meal_request.id) }
      .to have_enqueued_job(described_class).with(user.id, meal_request.id)

    args = enqueued_jobs.last.fetch(:args)
    expect(args).to eq([ user.id, meal_request.id ])
    serialized = args.to_json
    expect(serialized).not_to include(credential.api_key, credential.api_key.last(4), "Soft dinner", "Ann Lee")
  end

  it "is idempotent: a second run neither calls the provider nor duplicates meals" do
    adapter = with_adapter(FakeMealAdapter.meals(peanut_toast, lentil_soup))
    run_job
    expect { run_job }.not_to(change { meal_request.meal_suggestions.count })
    expect(adapter.calls).to eq(1)
  end

  it "replaces meals left behind by an interrupted run" do
    with_adapter(FakeMealAdapter.meals(lentil_soup))
    meal_request.update!(status: :running)
    create(:meal_suggestion, meal_request:, position: 0, dish: "Half-stored")
    run_job
    expect(meal_request.meal_suggestions.map(&:dish)).to eq([ "Lentil soup" ])
  end

  it "ignores another nurse's request" do
    other = create(:user)
    with_adapter(FakeMealAdapter.meals(lentil_soup))
    described_class.perform_now(other.id, meal_request.id)
    expect(meal_request.reload).to be_queued
  end

  it "fails with a plain message on an unexpected error and re-raises it for the logs" do
    described_class.adapter_factory = ->(_credential) { raise "boom #{credential.api_key}" }

    expect { described_class.perform_now(user.id, meal_request.id) }.to raise_error(RuntimeError)
    meal_request.reload
    expect(meal_request).to be_failed
    expect(meal_request.error_message).to eq("Something went wrong. Try again.")
    expect(meal_request.error_message).not_to include("boom")
  end

  it "runs through the queue" do
    with_adapter(FakeMealAdapter.meals(lentil_soup))
    perform_enqueued_jobs { described_class.perform_later(user.id, meal_request.id) }
    expect(meal_request.reload).to be_found
  end
end
