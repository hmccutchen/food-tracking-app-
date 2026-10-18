# Shared inputs for the adapter / suggester specs and their cassettes.
module MealSuggesterHelpers
  # Fixture model ids for the cassettes only; the app never hardcodes models.
  MODELS = { "gemini" => "gemini-2.5-flash", "anthropic" => "claude-sonnet-4-5", "openai" => "gpt-5-mini" }.freeze

  # Fake keys. Specs assert none of them ever lands in a cassette or an error.
  TEST_KEYS = {
    "gemini" => "AIzaTEST-gemini-never-real-0001",
    "anthropic" => "sk-ant-TEST-never-real-0002",
    "openai" => "sk-TEST-openai-never-real-0003"
  }.freeze

  PATIENT_NAMES = [ "Ann Lee", "Bertram" ].freeze

  # The real key and model when re-recording (VCR_RECORD=all), fakes otherwise.
  def adapter_credential(provider, key: nil, model: :default)
    env = provider.upcase
    ProviderCredential.new(
      provider:,
      api_key: key || ENV["#{env}_API_KEY"].presence || TEST_KEYS.fetch(provider),
      key_last4: "0000",
      model: model == :default ? (ENV["#{env}_MODEL"].presence || MODELS.fetch(provider)) : model
    )
  end

  def sample_suggest_args
    {
      terms: [ "milk", "peanut", "sodium" ],
      request: "Warm dinner for Ann Lee and Bertram, something soft. ann likes fish.",
      redact: PATIENT_NAMES,
      rejected: [ "butter" ]
    }
  end
end

RSpec.configure { |config| config.include MealSuggesterHelpers } if defined?(RSpec.configure)
