module Ai
  # Marker so Zeitwerk can load this file; the taxonomy is the classes below.
  module Errors; end

  # Base of every provider failure. The message is always the nurse-facing
  # plain_message; it never includes request headers, URLs or the API key.
  # Shared by key validation (M7) and meal suggestions (M8).
  class Error < StandardError
    attr_reader :provider, :status

    def self.code = "provider_error"

    def self.classes = [ InvalidKeyError, QuotaExceededError, RateLimitError, TimeoutError, ProviderError ]

    # Rebuilds an error from a stored last_error_code, for display.
    def self.from_code(code, provider)
      (classes.find { |klass| klass.code == code } || ProviderError).new(provider)
    end

    # Maps an HTTP error response to the taxonomy. Only status and body are
    # looked at; request headers (which carry the key) never are.
    def self.from_response(provider, status:, body:)
      klass = ResponseClassifier.new(provider.to_s, status.to_i, body.to_s).error_class
      klass.new(provider, status: status.to_i)
    end

    def initialize(provider, status: nil)
      @provider = provider.to_s
      @status = status
      super(plain_message)
    end

    def code = self.class.code
    def provider_name = Providers.name_for(provider)
    def plain_message = "Something went wrong talking to #{provider_name}."
  end

  class InvalidKeyError < Error
    def self.code = "invalid_key"
    def plain_message = "That key wasn't accepted. Check you copied the whole key for #{provider_name}."
  end

  class QuotaExceededError < Error
    def self.code = "quota_exceeded"
    def plain_message = "Your #{provider_name} account is out of credit or over its quota."
  end

  class RateLimitError < Error
    def self.code = "rate_limited"
    def plain_message = "#{provider_name} is busy right now (rate limit). Wait a minute and try again."
  end

  class TimeoutError < Error
    def self.code = "timeout"
    def plain_message = "#{provider_name} didn't answer in time. Try again."
  end

  # Fallback for 5xx, unreadable responses and anything unexpected.
  class ProviderError < Error; end

  # Status + body => error class, per provider.
  ResponseClassifier = Struct.new(:provider, :status, :body) do
    def error_class
      return QuotaExceededError if quota?
      return InvalidKeyError if invalid_key?
      return RateLimitError if status == 429

      ProviderError
    end

    private

    # Gemini answers a bad key with 400 + API_KEY_INVALID.
    def invalid_key? = [ 401, 403 ].include?(status) || (status == 400 && body.include?("API_KEY_INVALID"))

    def quota?
      case provider
      when "openai" then status == 429 && body.include?("insufficient_quota")
      when "anthropic" then status == 402 || ([ 400, 403, 429 ].include?(status) && body.match?(/credit balance|billing/i))
      when "gemini" then status == 429 && body.include?("RESOURCE_EXHAUSTED") && gemini_quota?
      else false
      end
    end

    # Gemini sends RESOURCE_EXHAUSTED for both per-minute limits and spent
    # quota. Per-day quota ids (or billing wording without ids) mean quota.
    def gemini_quota?
      ids = body.scan(/"quotaId"\s*:\s*"([^"]+)"/).flatten
      return ids.any? { |id| id.match?(/PerDay/i) } if ids.any?

      body.match?(/billing|credit/i)
    end
  end
end
