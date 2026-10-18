module Ai
  module Adapters
    # POST {base}/models/<model>:generateContent, key in x-goog-api-key.
    class Gemini < Base
      private

      def ruby_llm_provider = :gemini
      def configure(config, api_key) = config.gemini_api_key = api_key
    end
  end
end
