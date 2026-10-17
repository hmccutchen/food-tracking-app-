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

  it "keeps only chat-capable OpenAI models" do
    ids = %w[
      gpt-5-mini gpt-4o o3-mini text-embedding-3-small whisper-1 tts-1-hd dall-e-3 davinci-002 babbage-002
      omni-moderation-latest gpt-4o-transcribe gpt-4o-audio-preview gpt-4o-realtime-preview gpt-image-1
      gpt-4o-search-preview
    ]
    json = { "data" => ids.map { |id| { "id" => id } } + [ { "id" => nil } ] }
    expect(described_class.fetch("openai").parse_models(json)).to eq(%w[gpt-4o gpt-5-mini o3-mini])
  end
end
