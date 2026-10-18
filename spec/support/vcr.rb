require "vcr"

# Recorded provider responses. Cassettes in spec/cassettes/<provider>/ are
# hand-authored in each provider's real wire format (see the README there);
# playback only by default, so no spec reaches the network.
#
# Re-record with real keys:
#   VCR_RECORD=all GEMINI_API_KEY=... GEMINI_MODEL=... bundle exec rspec spec/models/ai/adapters_spec.rb
module VcrKeys
  # Header name => placeholder written to the cassette instead of the value.
  AUTH_HEADERS = {
    "Authorization" => "<AUTHORIZATION>",
    "X-Api-Key" => "<ANTHROPIC_API_KEY>",
    "X-Goog-Api-Key" => "<GEMINI_API_KEY>",
    "Openai-Organization" => "<OPENAI_ORGANIZATION>",
    "Openai-Project" => "<OPENAI_PROJECT>"
  }.freeze

  ENV_KEYS = %w[GEMINI_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY].freeze

  def self.record_mode = ENV.fetch("VCR_RECORD", "none").to_sym
  def self.recording? = record_mode != :none
end

VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join("spec/cassettes").to_s
  config.hook_into :webmock
  config.configure_rspec_metadata!
  # Capybara/Cuprite talk to the app on localhost.
  config.ignore_localhost = true
  config.allow_http_connections_when_no_cassette = false
  config.default_cassette_options = {
    record: VcrKeys.record_mode,
    # The body carries the prompt, which may change; specs check it directly.
    match_requests_on: %i[method uri],
    allow_unused_http_interactions: false
  }

  # Keys from the environment never reach a cassette, wherever they appear.
  VcrKeys::ENV_KEYS.each do |name|
    config.filter_sensitive_data("<#{name}>") { ENV[name].presence }
  end

  # Auth headers are replaced outright, whatever key was used.
  config.before_record do |interaction|
    VcrKeys::AUTH_HEADERS.each do |header, placeholder|
      interaction.request.headers[header] = [ placeholder ] if interaction.request.headers.key?(header)
    end
    # A key passed as a query parameter (?key=...) is scrubbed too.
    interaction.request.uri = interaction.request.uri.gsub(/([?&]key=)[^&]+/, '\1<API_KEY>')
  end
end
