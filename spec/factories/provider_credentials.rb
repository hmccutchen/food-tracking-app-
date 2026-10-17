FactoryBot.define do
  factory :provider_credential do
    user
    provider { "openai" }
    api_key { "sk-test-#{SecureRandom.hex(12)}WXYZ" }
    key_last4 { api_key.last(4) }
    available_models { %w[model-a model-b] }
    validated_at { 1.hour.ago }
    last_checked_at { validated_at }
  end
end
