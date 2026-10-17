require "rails_helper"

RSpec.describe Ai::KeyValidator do
  let(:key) { "secret-key-123456" }

  describe "the endpoints and auth headers" do
    it "asks OpenAI with a bearer token" do
      stub_models_success("openai")
      described_class.call("openai", key)
      expect(a_request(:get, "https://api.openai.com/v1/models")
        .with(headers: { "Authorization" => "Bearer #{key}" })).to have_been_made
    end

    it "asks Anthropic with x-api-key and the API version" do
      stub_models_success("anthropic")
      described_class.call("anthropic", key)
      expect(a_request(:get, "https://api.anthropic.com/v1/models?limit=1000")
        .with(headers: { "x-api-key" => key, "anthropic-version" => "2023-06-01" })).to have_been_made
    end

    it "asks Gemini with the key in a header, never the URL" do
      stub_models_success("gemini")
      described_class.call("gemini", key)
      expect(a_request(:get, "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000")
        .with(headers: { "x-goog-api-key" => key })).to have_been_made
      expect(Ai::Providers.fetch("gemini").models_url).not_to include("key=")
    end
  end

  %w[openai anthropic gemini].each do |provider|
    context "with #{provider}" do
      let(:name) { Ai::Providers.fetch(provider).name }

      it "returns the model ids from the list-models response, sorted" do
        stub_models_success(provider)
        expect(described_class.call(provider, key)).to eq(%w[model-a model-b])
      end

      it "maps 5xx to a provider error" do
        stub_models_failure(provider, status: 503)
        expect { described_class.call(provider, key) }
          .to raise_error(Ai::ProviderError, "Something went wrong talking to #{name}.")
      end

      it "maps a timeout to a timeout error" do
        stub_request(:get, models_url(provider)).to_timeout
        expect { described_class.call(provider, key) }
          .to raise_error(Ai::TimeoutError, "#{name} didn't answer in time. Try again.")
      end

      it "maps a read timeout to a timeout error" do
        stub_request(:get, models_url(provider)).to_raise(Net::ReadTimeout)
        expect { described_class.call(provider, key) }.to raise_error(Ai::TimeoutError)
      end

      it "maps an unreadable body to a provider error" do
        stub_request(:get, models_url(provider)).to_return(status: 200, body: "<html>oops")
        expect { described_class.call(provider, key) }.to raise_error(Ai::ProviderError)
      end

      it "maps a dropped connection to a provider error" do
        stub_request(:get, models_url(provider)).to_raise(Errno::ECONNRESET)
        expect { described_class.call(provider, key) }.to raise_error(Ai::ProviderError)
      end

      it "never puts the key in an error message or its cause" do
        stub_request(:get, models_url(provider)).to_raise(Net::OpenTimeout.new("execution expired #{key}"))
        expect { described_class.call(provider, key) }.to raise_error(Ai::Error) { |error|
          expect(error.message).not_to include(key)
          expect(error.cause).to be_nil
        }
      end

      it "treats a blank key as invalid without calling out" do
        expect { described_class.call(provider, "  ") }.to raise_error(Ai::InvalidKeyError)
      end
    end
  end

  describe "error mapping" do
    def error_for(provider, status, body)
      stub_models_failure(provider, status: status, body: body)
      described_class.call(provider, key)
    rescue Ai::Error => e
      e
    end

    context "with OpenAI" do
      it "maps 401 to invalid key" do
        error = error_for("openai", 401, { error: { code: "invalid_api_key", message: "Incorrect API key provided" } })
        expect(error).to be_a(Ai::InvalidKeyError)
        expect(error.plain_message).to eq("That key wasn't accepted. Check you copied the whole key for OpenAI.")
      end

      it "maps 403 to invalid key" do
        expect(error_for("openai", 403, { error: { message: "forbidden" } })).to be_a(Ai::InvalidKeyError)
      end

      it "maps 429 insufficient_quota to quota" do
        error = error_for("openai", 429, { error: { type: "insufficient_quota", code: "insufficient_quota" } })
        expect(error).to be_a(Ai::QuotaExceededError)
        expect(error.plain_message).to eq("Your OpenAI account is out of credit or over its quota.")
      end

      it "maps other 429s to rate limit" do
        error = error_for("openai", 429, { error: { code: "rate_limit_exceeded", message: "Rate limit reached" } })
        expect(error).to be_a(Ai::RateLimitError)
        expect(error.plain_message).to eq("OpenAI is busy right now (rate limit). Wait a minute and try again.")
      end
    end

    context "with Anthropic" do
      it "maps 401 to invalid key" do
        body = { type: "error", error: { type: "authentication_error", message: "invalid x-api-key" } }
        expect(error_for("anthropic", 401, body)).to be_a(Ai::InvalidKeyError)
      end

      it "maps a low credit balance to quota" do
        body = { type: "error", error: { type: "invalid_request_error",
                                         message: "Your credit balance is too low to access the Anthropic API." } }
        expect(error_for("anthropic", 400, body)).to be_a(Ai::QuotaExceededError)
      end

      it "maps a billing error to quota" do
        body = { type: "error", error: { type: "billing_error", message: "Billing issue" } }
        expect(error_for("anthropic", 402, body)).to be_a(Ai::QuotaExceededError)
      end

      it "maps 429 to rate limit" do
        body = { type: "error", error: { type: "rate_limit_error", message: "Number of requests exceeded" } }
        expect(error_for("anthropic", 429, body)).to be_a(Ai::RateLimitError)
      end

      it "maps 529 overloaded to a provider error" do
        body = { type: "error", error: { type: "overloaded_error", message: "Overloaded" } }
        expect(error_for("anthropic", 529, body)).to be_a(Ai::ProviderError)
      end
    end

    context "with Gemini" do
      it "maps 400 API_KEY_INVALID to invalid key" do
        body = { error: { code: 400, message: "API key not valid. Please pass a valid API key.", status: "INVALID_ARGUMENT",
                          details: [ { "@type": "type.googleapis.com/google.rpc.ErrorInfo", reason: "API_KEY_INVALID" } ] } }
        error = error_for("gemini", 400, body)
        expect(error).to be_a(Ai::InvalidKeyError)
        expect(error.plain_message).to include("Google Gemini")
      end

      it "maps other 400s to a provider error" do
        body = { error: { code: 400, message: "Bad request", status: "INVALID_ARGUMENT" } }
        expect(error_for("gemini", 400, body)).to be_a(Ai::ProviderError)
      end

      it "maps 403 PERMISSION_DENIED to invalid key" do
        expect(error_for("gemini", 403, { error: { status: "PERMISSION_DENIED" } })).to be_a(Ai::InvalidKeyError)
      end

      it "maps a spent daily quota to quota" do
        body = { error: { code: 429, status: "RESOURCE_EXHAUSTED", message: "You exceeded your current quota.",
                          details: [ { "@type": "type.googleapis.com/google.rpc.QuotaFailure",
                                      violations: [ { quotaId: "GenerateRequestsPerDayPerProjectPerModel-FreeTier" } ] } ] } }
        expect(error_for("gemini", 429, body)).to be_a(Ai::QuotaExceededError)
      end

      it "maps a billing RESOURCE_EXHAUSTED without quota ids to quota" do
        body = { error: { code: 429, status: "RESOURCE_EXHAUSTED", message: "Check your plan and billing details." } }
        expect(error_for("gemini", 429, body)).to be_a(Ai::QuotaExceededError)
      end

      it "maps a per-minute RESOURCE_EXHAUSTED to rate limit" do
        body = { error: { code: 429, status: "RESOURCE_EXHAUSTED", message: "You exceeded your current quota.",
                          details: [ { "@type": "type.googleapis.com/google.rpc.QuotaFailure",
                                      violations: [ { quotaId: "GenerateRequestsPerMinutePerProjectPerModel-FreeTier" } ] } ] } }
        expect(error_for("gemini", 429, body)).to be_a(Ai::RateLimitError)
      end
    end
  end
end
