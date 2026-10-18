FactoryBot.define do
  factory :food do
    sequence(:fdc_id) { |n| 900_000 + n }
    source { "sr_legacy" }
    data_type { "sr_legacy_food" }
    sequence(:description) { |n| "Food #{n}, raw" }
    category { "Nut and Seed Products" }
    publication_date { Date.new(2019, 4, 1) }
    imported_at { Time.zone.local(2026, 10, 1, 9) }
    raw { { "fdc_id" => fdc_id.to_s, "description" => description } }
    match_type { "unresolved" }
    match_reason { "no ingredient match for '#{description}'" }
  end
end
