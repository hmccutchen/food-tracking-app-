require "rails_helper"

RSpec.describe "RubyLLM global configuration" do
  let(:config) { RubyLLM.config }

  it "holds no API keys, tokens or secrets" do
    credential_options = RubyLLM::Configuration.options.grep(/(_key|_token|_secret|_credential_provider|_id)\z/)
    expect(credential_options).to include(:gemini_api_key, :anthropic_api_key, :openai_api_key)
    expect(credential_options.index_with { |option| config.public_send(option) }.compact).to eq({})
  end

  it "logs at WARN or quieter, so request bodies are never logged" do
    expect(config.log_level).to be >= Logger::WARN
    expect(RubyLLM.logger.level).to be >= Logger::WARN
    expect(RubyLLM.logger.debug?).to be(false)
    expect(config.log_stream_debug).to be(false)
  end

  it "fails a slow call plainly and leaves retries to us" do
    expect(config.request_timeout).to eq(45)
    expect(config.max_retries).to be <= 1
  end

  it "gives each call its own config copy, leaving the global one keyless" do
    context = RubyLLM.context { |c| c.gemini_api_key = "AIzaTEST-context-only" }
    expect(context.config.gemini_api_key).to eq("AIzaTEST-context-only")
    expect(config.gemini_api_key).to be_nil
    expect(context.config.inspect).not_to include("AIzaTEST-context-only")
  end
end
