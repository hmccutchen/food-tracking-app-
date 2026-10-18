FactoryBot.define do
  factory :meal_request do
    user
    patient_ids { [ create(:patient, user:).id ] }
    request_text { "dinner, soft foods" }
    status { "queued" }
  end

  factory :meal_suggestion do
    meal_request
    sequence(:position) { |n| n }
    dish { "Lentil soup" }
    ingredients { [ "red lentils", "carrot" ] }
    prep_notes { [] }
    kept { true }
    transient do
      result { Evaluation::GroupResult.new(patient_results: [], ingredients:) }
    end
    tier { result.tier.to_s }
    result_json { result.to_h.to_json }
    profile_versions { result.profile_versions.transform_keys(&:to_s) }
    evaluated_at { result.evaluated_at }
  end
end
