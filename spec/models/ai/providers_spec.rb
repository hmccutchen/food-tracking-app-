require "rails_helper"

RSpec.describe Ai::Providers do
  it "lists gemini, anthropic and openai with names and key hints" do
    expect(described_class.keys).to eq(%w[gemini anthropic openai])
    expect(described_class.all.map(&:key_hint)).to all(be_present)
    expect(described_class.name_for("openai")).to eq("OpenAI")
  end

  it "drops Gemini models that can't generate content and strips the models/ prefix" do
    json = { "models" => [
      { "name" => "models/b", "supportedGenerationMethods" => [ "generateContent" ] },
      { "name" => "models/e", "supportedGenerationMethods" => [ "embedContent" ] }
    ] }
    expect(described_class.fetch("gemini").parse_models(json)).to eq([ "b" ])
  end
end
