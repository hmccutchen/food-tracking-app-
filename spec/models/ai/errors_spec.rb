require "rails_helper"

RSpec.describe Ai::Error do
  it "gives every error a plain message naming the provider" do
    messages = described_class.classes.map { |klass| klass.new("anthropic").plain_message }
    expect(messages).to eq([
      "That key wasn't accepted. Check you copied the whole key for Anthropic Claude.",
      "Your Anthropic Claude account is out of credit or over its quota.",
      "Anthropic Claude is busy right now (rate limit). Wait a minute and try again.",
      "Anthropic Claude didn't answer in time. Try again.",
      "Anthropic Claude sent back something we couldn't read. Trying again may help.",
      "Pick a model for Anthropic Claude in AI settings.",
      "Something went wrong talking to Anthropic Claude."
    ])
  end

  it "uses the plain message as the exception message" do
    expect(Ai::RateLimitError.new("openai").message).to eq(Ai::RateLimitError.new("openai").plain_message)
  end

  it "round-trips through a stored code, falling back to a provider error" do
    expect(described_class.from_code("quota_exceeded", "gemini")).to be_a(Ai::QuotaExceededError)
    expect(described_class.from_code("something-new", "gemini")).to be_a(Ai::ProviderError)
  end

  it "keeps the status but never the body in the error" do
    error = described_class.from_response("openai", status: 500, body: "secret-ish body")
    expect(error).to be_a(Ai::ProviderError)
    expect(error.status).to eq(500)
    expect(error.message).not_to include("secret-ish")
  end
end
