# One "Suggest meals" request from the nurse for a group of her patients.
# SuggestMealsJob fills it in; the request text and the blocking conflicts are
# health data, so both are encrypted. error_message is always plain words.
class MealRequest < ApplicationRecord
  STATUSES = %w[queued running found not_found failed].freeze
  PENDING = %w[queued running].freeze
  # Error codes the nurse fixes in AI settings, so the card links there.
  SETTINGS_ERRORS = %w[no_provider model_missing invalid_key quota_exceeded].freeze

  belongs_to :user
  has_many :meal_suggestions, -> { order(:position) }, dependent: :delete_all, inverse_of: :meal_request

  encrypts :request_text
  serialize :blocking_conflicts, coder: JSON, type: Array
  encrypts :blocking_conflicts

  enum :status, STATUSES.index_with(&:itself), validate: true

  validate :some_patients
  validates :request_text, length: { maximum: 500 }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def pending? = PENDING.include?(status)
  def finished? = !pending?
  def settings_error? = failed? && SETTINGS_ERRORS.include?(error_code)

  def kept_suggestions = meal_suggestions.select(&:kept)
  def dropped_suggestions = meal_suggestions.reject(&:kept)

  def provider_name = provider.present? ? Ai::Providers.name_for(provider) : "the AI"

  # The requested patients that are still on file, in the order picked.
  def current_patient_ids
    existing = user.patients.where(id: patient_ids).pluck(:id)
    patient_ids & existing
  end

  # { patient_id => display name } for display; deleted patients are absent.
  def patient_names
    @patient_names ||= user.patients.where(id: patient_ids).to_h { |patient| [ patient.id, patient.display_name ] }
  end

  # A patient changed or was removed since these meals were checked.
  def stale?
    return false if pending? || meal_suggestions.empty?

    Evaluation::GroupResult.stale_for?(profile_versions) || meal_suggestions.any?(&:stale?)
  end

  # Re-runs only the engine on the stored ingredients for the patients still
  # on file. No AI call. A kept meal can become a conflict; it stays listed
  # (as "Now a conflict"), never silently hidden.
  def recheck!
    ids = current_patient_ids
    engine = Evaluation::Engine.new(ids)
    transaction do
      meal_suggestions.each { |suggestion| suggestion.store_result!(engine.evaluate(suggestion.ingredients)) }
      stamp = Patient.where(id: ids).pluck(:id, :profile_version).to_h
      changes = { profile_versions: stamp.transform_keys(&:to_s) }
      if not_found?
        changes[:blocking_conflicts] = dropped_suggestions.flat_map(&:blocking_reasons).uniq
      end
      update!(changes)
    end
  end

  def broadcast_card
    Turbo::StreamsChannel.broadcast_replace_to(self, target: ActionView::RecordIdentifier.dom_id(self),
      partial: "meal_requests/meal_request", locals: { meal_request: self })
  end

  private

  def some_patients
    errors.add(:base, "Pick at least one patient first.") if patient_ids.blank?
  end
end
