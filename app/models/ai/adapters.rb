module Ai
  # One thin RubyLLM wrapper per provider. Each sends a MealSuggester::Prompt
  # with only that nurse's key and model, and returns the raw reply text.
  module Adapters
    def self.for(credential)
      { "gemini" => Gemini, "anthropic" => Anthropic, "openai" => OpenAI }
        .fetch(credential.provider.to_s) { raise ArgumentError, "no adapter for #{credential.provider.inspect}" }
        .new(credential)
    end
  end
end
