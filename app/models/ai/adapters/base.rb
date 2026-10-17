module Ai
  module Adapters
    # Sends one prompt through RubyLLM and returns the reply text. Never
    # parses meals (MealSuggester::Parser does) and never retries (the
    # caller does). Every failure leaves as an Ai::Error with a plain
    # message; the RubyLLM/Faraday exception is dropped (`cause: nil`) so the
    # request, its headers and the key can't ride along into a log.
    class Base
      # RubyLLM classes that tell us what happened when the response body
      # alone doesn't (e.g. Gemini's "API key not valid" without a reason).
      CLASS_HINTS = {
        RubyLLM::UnauthorizedError => InvalidKeyError,
        RubyLLM::ForbiddenError => InvalidKeyError,
        RubyLLM::PaymentRequiredError => QuotaExceededError,
        RubyLLM::RateLimitError => RateLimitError
      }.freeze

      def initialize(credential)
        @credential = credential
      end

      def provider = @credential.provider.to_s

      # prompt: a MealSuggester::Prompt. Returns the model's text reply.
      def complete(prompt)
        model = @credential.model.to_s.strip
        raise ModelMissingError.new(provider) if model.empty?
        raise InvalidKeyError.new(provider) if api_key.empty?

        chat(model).with_schema(prompt.schema).ask(prompt.text).content.to_s
      rescue RubyLLM::Error => e
        raise map_response_error(e), cause: nil
      rescue Faraday::TimeoutError, ::Timeout::Error
        raise TimeoutError.new(provider), cause: nil
      rescue Faraday::ConnectionFailed => e
        klass = timeout?(e) ? TimeoutError : ProviderError
        raise klass.new(provider), cause: nil
      rescue Faraday::ParsingError
        raise MalformedResponseError.new(provider), cause: nil
      rescue Faraday::Error, RubyLLM::ConfigurationError, RubyLLM::ModelNotFoundError, SocketError, SystemCallError,
             IOError, OpenSSL::SSL::SSLError
        raise ProviderError.new(provider), cause: nil
      end

      # Never show the key, even in a console.
      def inspect = "#<#{self.class.name} provider=#{provider} model=#{@credential.model.inspect}>"

      private

      def api_key = @credential.api_key.to_s.strip

      # An isolated config copy holding only this user's key; the global
      # config (keyless, see config/initializers/ruby_llm.rb) is untouched.
      # assume_model_exists: we never hardcode models, so RubyLLM's registry
      # is not consulted for whether this one is real.
      def chat(model)
        key = api_key
        context = RubyLLM.context { |config| configure(config, key) }
        context.chat(model:, provider: ruby_llm_provider, assume_model_exists: true)
      end

      # Status and body decide, via the same classifier key validation uses
      # (Ai::Error.from_response). A 2xx that RubyLLM still couldn't turn into
      # a message is a malformed reply.
      def map_response_error(error)
        response = error.response
        status = response&.status
        return MalformedResponseError.new(provider, status:) if status&.between?(200, 299)

        mapped = Error.from_response(provider, status:, body: body_text(response)) if response
        return mapped if mapped && !mapped.instance_of?(ProviderError)

        hint = CLASS_HINTS.find { |klass, _| error.is_a?(klass) }&.last
        (hint || ProviderError).new(provider, status:)
      end

      # The error middleware sees the body before JSON parsing, but be ready
      # for either shape so the classifier reads real JSON text.
      def body_text(response)
        body = response.body
        body.is_a?(String) ? body : body.to_json
      end

      def timeout?(error)
        wrapped = error.wrapped_exception
        wrapped.is_a?(::Timeout::Error) || error.message.match?(/timed? ?out/i)
      end

      def ruby_llm_provider = raise(NotImplementedError)
      def configure(_config, _api_key) = raise(NotImplementedError)
    end
  end
end
