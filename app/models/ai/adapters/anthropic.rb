module Ai
  module Adapters
    # POST https://api.anthropic.com/v1/messages, key in x-api-key.
    class Anthropic < Base
      private

      def ruby_llm_provider = :anthropic
      def configure(config, api_key) = config.anthropic_api_key = api_key
    end
  end
end
