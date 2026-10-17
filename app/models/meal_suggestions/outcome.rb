module MealSuggestions
  # What one Pipeline run produced. Plain data: the tiers inside each
  # group_result were set by Evaluation::Engine, never by the AI.
  #
  # kept:     meals with no conflict (possible_conflict / unknown / no flags are
  #           kept and labelled; the nurse decides).
  # dropped:  meals whose group tier was conflict.
  # attempts: one Attempt per call to the provider, in order.
  # final_error: the Ai::Error of the last attempt when it failed and nothing
  #           was kept; nil otherwise.
  Outcome = Data.define(:kept, :dropped, :attempts, :final_error, :profile_versions) do
    def found? = kept.any?

    # Unique conflict reasons across every dropped meal, for the "couldn't
    # find a meal" card ("peanut butter is a peanut (allergy)").
    def blocking_conflicts = dropped.flat_map(&:reasons).uniq
  end
end
