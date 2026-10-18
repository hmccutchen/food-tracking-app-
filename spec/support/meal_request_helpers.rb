# Builds a finished MealRequest whose meals were checked by the real engine,
# without any AI call: stored_meal_request(user, [ ann ], kept: [ [ "Soup", [ "carrot" ] ] ]).
module MealRequestHelpers
  def stored_meal_request(user, patients, kept: [], dropped: [], status: nil, **attrs)
    engine = Evaluation::Engine.new(patients)
    request = create(:meal_request, user:, patient_ids: patients.map(&:id), status: status || (kept.any? ? "found" : "not_found"),
      provider: "openai", profile_versions: patients.to_h { |patient| [ patient.id.to_s, patient.reload.profile_version ] },
      **attrs)
    rows = kept.map { |meal| [ meal, true ] } + dropped.map { |meal| [ meal, false ] }
    rows.each_with_index do |((dish, ingredients, prep_notes), keep), index|
      result = engine.evaluate(ingredients)
      request.meal_suggestions.create!(dish:, ingredients:, prep_notes: prep_notes || [], kept: keep, position: index,
        **MealSuggestion.attributes_for(result))
    end
    if request.not_found? && !attrs.key?(:blocking_conflicts)
      request.update!(blocking_conflicts: request.dropped_suggestions.flat_map(&:blocking_reasons).uniq)
    end
    request.reload
  end
end

RSpec.configure { |config| config.include MealRequestHelpers }
