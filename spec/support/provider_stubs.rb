# WebMock helpers for the providers' list-models endpoints. No real network.
module ProviderStubs
  MODELS_BODIES = {
    "openai" => { object: "list", data: [ { id: "model-b", object: "model" }, { id: "model-a", object: "model" } ] },
    "anthropic" => { data: [ { id: "model-b", type: "model" }, { id: "model-a", type: "model" } ], has_more: false },
    "gemini" => { models: [
      { name: "models/model-b", supportedGenerationMethods: %w[generateContent countTokens] },
      { name: "models/model-a", supportedGenerationMethods: %w[generateContent] },
      { name: "models/embedder", supportedGenerationMethods: %w[embedContent] }
    ] }
  }.freeze

  def models_url(provider) = Ai::Providers.fetch(provider).models_url

  def stub_models_success(provider, body: MODELS_BODIES.fetch(provider))
    stub_request(:get, models_url(provider))
      .to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_models_failure(provider, status:, body: {})
    stub_request(:get, models_url(provider))
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end
end

RSpec.configure { |config| config.include ProviderStubs }
