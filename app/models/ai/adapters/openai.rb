module Ai
  module Adapters
    # POST https://api.openai.com/v1/responses (RubyLLM's default protocol for
    # OpenAI), key in the Authorization bearer header.
    class OpenAI < Base
      private

      def ruby_llm_provider = :openai
      def configure(config, api_key) = config.openai_api_key = api_key
    end
  end
end
