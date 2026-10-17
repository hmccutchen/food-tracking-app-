module Ai
  # The one place that knows each provider's endpoints and auth headers.
  # Model names are never listed here: they come from the provider's own
  # list-models response and the nurse picks one.
  module Providers
    Provider = Data.define(:key, :name, :models_url, :key_hint, :auth, :model_parser) do
      # Headers that carry the key. Built per request; never interpolated into
      # errors or logs.
      def auth_headers(api_key) = auth.call(api_key)

      def parse_models(json) = model_parser.call(json).compact.uniq.sort
    end

    ALL = [
      Provider.new(
        key: "gemini",
        name: "Google Gemini",
        # Key goes in a header, never the query string, so it can't land in a URL or log.
        models_url: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000",
        key_hint: "Usually starts with “AIza”. Create one in Google AI Studio.",
        auth: ->(api_key) { { "x-goog-api-key" => api_key } },
        model_parser: lambda { |json|
          Array(json["models"])
            .select { |m| m["supportedGenerationMethods"].nil? || m["supportedGenerationMethods"].include?("generateContent") }
            .map { |m| m["name"].to_s.delete_prefix("models/").presence }
        }
      ),
      Provider.new(
        key: "anthropic",
        name: "Anthropic Claude",
        models_url: "https://api.anthropic.com/v1/models?limit=1000",
        key_hint: "Usually starts with “sk-ant-”. Create one in the Anthropic Console.",
        auth: ->(api_key) { { "x-api-key" => api_key, "anthropic-version" => "2023-06-01" } },
        model_parser: ->(json) { Array(json["data"]).map { |m| m["id"].presence } }
      ),
      Provider.new(
        key: "openai",
        name: "OpenAI",
        models_url: "https://api.openai.com/v1/models",
        key_hint: "Usually starts with “sk-”. Create one in the OpenAI dashboard.",
        auth: ->(api_key) { { "Authorization" => "Bearer #{api_key}" } },
        model_parser: ->(json) { Array(json["data"]).map { |m| m["id"].presence } }
      )
    ].index_by(&:key).freeze

    def self.all = ALL.values
    def self.keys = ALL.keys
    def self.fetch(key) = ALL.fetch(key.to_s)
    def self.name_for(key) = ALL[key.to_s]&.name || "the AI provider"
  end
end
