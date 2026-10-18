# Runs MealSuggestions::Pipeline for one MealRequest and stores what it found.
#
#   SuggestMealsJob.perform_later(user.id, meal_request.id)
#
# Arguments are ids only: job arguments are serialized into the queue table
# and logs, so the key, the credential and the request text never go there.
# The credential is loaded at run time with Ai::CredentialLookup. Tiers come
# from Evaluation::Engine inside the pipeline; nothing here sets one.
class SuggestMealsJob < ApplicationJob
  queue_as :default

  GENERIC_ERROR = "Something went wrong. Try again.".freeze
  NO_PROVIDER = "No AI provider is set up yet. Add a key and pick a model in AI settings.".freeze
  NO_PATIENTS = "None of these patients are on file any more.".freeze

  # Test seam only: ->(credential) { adapter }. nil uses the real adapter.
  class_attribute :adapter_factory, instance_accessor: false, default: nil

  def perform(user_id, meal_request_id)
    @meal_request = MealRequest.find_by(id: meal_request_id, user_id:)
    # Idempotent: a finished request is never run (or stored) twice.
    return if @meal_request.nil? || @meal_request.finished?

    @meal_request.update!(status: :running)
    @meal_request.broadcast_card
    run(user_id)
  rescue StandardError
    # Plain words for the nurse; the exception itself goes to the logs only.
    mark_unexpected_failure
    raise
  end

  private

  def run(user_id)
    credential = Ai::CredentialLookup.for(user_id)
    return fail_with(NO_PROVIDER, "no_provider") if credential.nil?

    if credential.model.to_s.strip.empty?
      error = Ai::ModelMissingError.new(credential.provider)
      return fail_with(error.plain_message, error.code, provider: credential.provider)
    end

    patients = User.find(user_id).patients.where(id: @meal_request.patient_ids).to_a
    return fail_with(NO_PATIENTS, "no_patients") if patients.empty?

    # Pipeline redacts the patients' names from the request text itself.
    outcome = MealSuggestions::Pipeline.new(credential:, patients:, request: @meal_request.request_text.to_s,
      adapter: self.class.adapter_factory&.call(credential)).call
    store(outcome, credential.provider)
  end

  def store(outcome, provider)
    stored = MealRequest.transaction do
      # A second run that raced this one finished first: keep its results.
      @meal_request.lock!
      replace_suggestions(outcome, provider) if @meal_request.pending?
    end
    @meal_request.meal_suggestions.reset
    @meal_request.broadcast_card if stored
  end

  def replace_suggestions(outcome, provider)
    @meal_request.meal_suggestions.delete_all
    rows = outcome.kept.map { |kept| row(kept, true) } + outcome.dropped.map { |dropped| row(dropped, false) }
    rows.each_with_index { |attrs, index| @meal_request.meal_suggestions.create!(attrs.merge(position: index)) }
    @meal_request.update!(final_attributes(outcome).merge(provider:, attempts_count: outcome.attempts.size,
      profile_versions: outcome.profile_versions.transform_keys(&:to_s)))
  end

  def final_attributes(outcome)
    if outcome.found?
      { status: :found }
    elsif outcome.final_error
      { status: :failed, error_message: outcome.final_error.plain_message, error_code: outcome.final_error.code }
    else
      { status: :not_found, blocking_conflicts: outcome.blocking_conflicts }
    end
  end

  def row(entry, kept)
    suggestion = entry.suggestion
    { dish: suggestion.dish, ingredients: suggestion.ingredients, prep_notes: suggestion.prep_notes, kept: }
      .merge(MealSuggestion.attributes_for(entry.group_result))
  end

  def mark_unexpected_failure
    fail_with(GENERIC_ERROR, "unexpected") if @meal_request&.reload&.pending?
  rescue StandardError
    nil # the original error is the one worth raising
  end

  def fail_with(message, code, provider: nil)
    @meal_request.update!(status: :failed, error_message: message, error_code: code,
      provider: provider || @meal_request.provider)
    @meal_request.broadcast_card
  end
end
