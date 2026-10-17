module Evaluation
  # The outcome for all selected patients. Worst case wins: the group tier is
  # never softer than any one patient's tier.
  GroupResult = Data.define(:patient_results, :ingredients, :profile_versions, :missing_patient_ids, :evaluated_at) do
    const_set(:NO_FLAGS_SUMMARY, "No flags found — this isn't a guarantee")

    # True when any recorded patient's current profile_version differs from the
    # stamp, or the patient no longer exists. Keys may be strings (e.g. from JSON).
    def self.stale_for?(profile_versions)
      stamp = profile_versions.to_h.transform_keys { |id| Integer(id) }
      return false if stamp.empty?

      current = Patient.where(id: stamp.keys).pluck(:id, :profile_version).to_h
      stamp.any? { |id, version| current[id] != Integer(version) }
    end

    # missing_patient_ids: selected patients that no longer existed when evaluated.
    def initialize(patient_results:, ingredients:, profile_versions: nil, missing_patient_ids: [],
                   evaluated_at: Time.current)
      profile_versions ||= patient_results.to_h { |result| [ result.patient_id, result.profile_version ] }
      super(patient_results: patient_results.freeze, ingredients: ingredients&.freeze,
        profile_versions: profile_versions.freeze, missing_patient_ids: missing_patient_ids.freeze, evaluated_at:)
    end

    def tier = Tier.worst(patient_results.map(&:tier))

    def for_patient(patient_id) = patient_results.find { |result| result.patient_id == patient_id }

    # Active conflict flags across all patients (the ingredients an AI retry must avoid).
    def conflicts
      patient_results.flat_map(&:active_flags).select { |flag| flag.tier == Tier::CONFLICT }
    end

    def blocking_ingredients = conflicts.filter_map(&:ingredient).uniq

    def no_flags? = tier.none?

    def summary
      case tier
      when Tier::NONE then self.class::NO_FLAGS_SUMMARY
      when Tier::CONFLICT then "Conflict found"
      when Tier::POSSIBLE_CONFLICT then "Possible conflict — check the label"
      else "Some ingredients could not be checked"
      end
    end

    # A selected patient was already missing, or a stamped profile changed since.
    def stale? = missing_patient_ids.any? || self.class.stale_for?(profile_versions)
  end
end
