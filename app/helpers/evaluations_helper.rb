module EvaluationsHelper
  TIER_LABELS = {
    conflict: "Conflict",
    possible_conflict: "Possible conflict",
    unknown: "Unknown",
    none: Evaluation::GroupResult::NO_FLAGS_SUMMARY
  }.freeze

  # Plain words for a tier. The label is always shown; color is only a hint.
  def tier_label(tier)
    TIER_LABELS.fetch(Evaluation::Tier.fetch(tier).to_sym)
  end

  def tier_badge(tier)
    tier = Evaluation::Tier.fetch(tier)
    tag.span(tier_label(tier), class: "tier-badge", data: { tier: tier.to_s })
  end

  # patients: { id => name or Patient }; keys may be integers or strings.
  def evaluation_patient_name(patients, patient_id)
    value = patients[patient_id] || patients[patient_id.to_s]
    value = value.display_name if value.respond_to?(:display_name)
    value.presence || "Patient no longer on file"
  end
end
