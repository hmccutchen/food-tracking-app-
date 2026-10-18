# One meal the AI suggested for a MealRequest, with the engine's verdict on it.
# result_json is the serialized Evaluation::GroupResult (flag reasons name
# restriction terms, so it is encrypted). The tier always comes from the
# engine; the AI's prep_notes are shown as advice only.
class MealSuggestion < ApplicationRecord
  TIERS = Evaluation::Tier::ALL.map(&:to_s).freeze

  belongs_to :meal_request

  encrypts :result_json

  validates :dish, :result_json, :evaluated_at, presence: true
  validates :tier, inclusion: { in: TIERS }
  validates :kept, inclusion: { in: [ true, false ] }

  def self.attributes_for(result)
    { result_json: result.to_h.to_json, tier: result.tier.to_s,
      profile_versions: result.profile_versions.transform_keys(&:to_s), evaluated_at: result.evaluated_at }
  end

  def group_result
    @group_result ||= Evaluation::GroupResult.from_h(JSON.parse(result_json))
  end

  def store_result!(result)
    @group_result = nil
    update!(self.class.attributes_for(result))
  end

  def stale? = group_result.stale?

  # Kept when suggested, but a later re-check found a conflict.
  def now_conflict? = kept && tier == "conflict"

  def blocking_reasons = group_result.conflicts.map(&:reason).uniq
end
