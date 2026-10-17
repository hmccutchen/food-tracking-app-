FactoryBot.define do
  factory :patient do
    user
    sequence(:display_name) { |n| "Patient #{n}" }
  end

  factory :restriction do
    patient
    kind { :allergy }
    term { "peanut" }
  end
end
