require "rails_helper"

RSpec.describe Ai::Adapters do
  cassettes = Rails.root.join("spec/cassettes")

  endpoints = {
    "gemini" => %r{\Ahttps://generativelanguage\.googleapis\.com/v1beta/models/[^/]+:generateContent\z},
    "anthropic" => %r{\Ahttps://api\.anthropic\.com/v1/messages\z},
    "openai" => %r{\Ahttps://api\.openai\.com/v1/responses\z}
  }.freeze

  auth = {
    "gemini" => ->(key) { { "x-goog-api-key" => key } },
    "anthropic" => ->(key) { { "x-api-key" => key, "anthropic-version" => "2023-06-01" } },
    "openai" => ->(key) { { "Authorization" => "Bearer #{key}" } }
  }.freeze

  %w[gemini anthropic openai].each do |provider|
    describe provider do
      let(:provider) { provider }
      let(:endpoint) { endpoints.fetch(provider) }
      let(:auth_headers) { auth.fetch(provider) }
      let(:name) { Ai::Providers.fetch(provider).name }
      let(:credential) { adapter_credential(provider) }
      # Always a bad key, even when re-recording, so invalid_key records live.
      let(:bad_credential) { adapter_credential(provider, key: "bad-key-for-#{provider}-9999") }

      def suggest(with: credential) = MealSuggester.new(with).suggest(**sample_suggest_args)

      def sent_body
        request = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last
        JSON.parse(request.body).to_json # normalised, so escapes don't hide words
      end

      def expect_failure(klass, cassette: nil, with: credential)
        run = -> { expect { suggest(with:) }.to raise_error(klass) { |error| yield error if block_given? ; check_error(error, with) } }
        cassette ? VCR.use_cassette("#{provider}/#{cassette}", &run) : run.call
      end

      def check_error(error, used)
        expect(error.message).not_to include(used.api_key)
        expect(error.full_message).not_to include(used.api_key)
        expect(error.cause).to be_nil
        expect(error.provider).to eq(provider)
      end

      it "returns meals from a recorded success, sending only this user's key and model" do
        result = VCR.use_cassette("#{provider}/success") { suggest }
        expect(result.suggestions.size).to eq(3)
        result.suggestions.each do |meal|
          expect(meal.dish).to be_present
          expect(meal.ingredients).to all(be_a(String).and(be_present))
          expect(meal.prep_notes).to all(be_a(String))
        end
        expect(a_request(:post, endpoint).with(headers: auth_headers.call(credential.api_key))).to have_been_made.once
        expect(RubyLLM.config.public_send(:"#{provider}_api_key")).to be_nil
      end

      it "sends the terms and rejected ingredients but never a patient name" do
        VCR.use_cassette("#{provider}/success") { suggest }
        body = sent_body
        expect(body).to include("- milk", "- peanut", "- sodium", "- butter", "the patient")
        expect(body).not_to match(/ann|lee|bertram/i)
        expect(body).to include(%("meal_suggestions")) if provider == "openai"
        expect(body).to include("json_schema").or include("responseJsonSchema")
      end

      it "maps an invalid key" do
        expect_failure(Ai::InvalidKeyError, cassette: "invalid_key", with: bad_credential) do |error|
          expect(error.message).to eq("That key wasn't accepted. Check you copied the whole key for #{name}.")
        end
      end

      it "maps a rate limit" do
        expect_failure(Ai::RateLimitError, cassette: "rate_limit") { |error| expect(error.status).to eq(429) }
      end

      it "maps spent quota or credit" do
        expect_failure(Ai::QuotaExceededError, cassette: "quota") do |error|
          expect(error.message).to eq("Your #{name} account is out of credit or over its quota.")
        end
      end

      %w[prose broken_json wrong_shape].each do |kind|
        it "maps a malformed reply (#{kind.tr('_', ' ')})" do
          expect_failure(Ai::MalformedResponseError, cassette: "malformed_#{kind}")
        end
      end

      it "maps a timeout" do
        stub_request(:post, endpoint).to_timeout
        expect_failure(Ai::TimeoutError) { |error| expect(error.message).to eq("#{name} didn't answer in time. Try again.") }
      end

      it "maps a read timeout" do
        stub_request(:post, endpoint).to_raise(Net::ReadTimeout)
        expect_failure(Ai::TimeoutError)
      end

      it "maps server errors, overload and an unreachable host to a provider error" do
        [ 500, 503, 529 ].each do |status|
          stub_request(:post, endpoint).to_return(status:, body: { error: { message: "busy" } }.to_json,
                                                                   headers: { "Content-Type" => "application/json" })
          expect_failure(Ai::ProviderError) { |error| expect(error).to be_instance_of(Ai::ProviderError) }
        end
        stub_request(:post, endpoint).to_raise(SocketError)
        expect_failure(Ai::ProviderError)
      end

      it "maps an unreadable HTTP body to a malformed reply" do
        stub_request(:post, endpoint).to_return(status: 200, body: "<html>oops",
                                                                 headers: { "Content-Type" => "application/json" })
        expect_failure(Ai::MalformedResponseError)
      end

      it "asks the nurse to pick a model instead of guessing one" do
        expect_failure(Ai::ModelMissingError, with: adapter_credential(provider, model: " ")) do |error|
          expect(error.message).to eq("Pick a model for #{name} in AI settings.")
        end
        expect(a_request(:any, //)).not_to have_been_made
      end

      it "keeps two users' keys apart" do
        stub_request(:post, endpoint).to_return(status: 500)
        [ "#{provider}-user-one-key-1111", "#{provider}-user-two-key-2222" ].each do |key|
          expect { suggest(with: adapter_credential(provider, key:)) }.to raise_error(Ai::ProviderError)
          expect(a_request(:post, endpoint).with(headers: auth_headers.call(key))).to have_been_made.once
        end
      end
    end
  end

  describe "the cassettes" do
    let(:files) { cassettes.glob("**/*.yml") }

    it "covers every provider and failure" do
      names = %w[success invalid_key rate_limit quota malformed_prose malformed_broken_json malformed_wrong_shape]
      expected = %w[gemini anthropic openai].product(names).map { |provider, name| cassettes.join(provider, "#{name}.yml") }
      expect(files).to match_array(expected)
    end

    it "never contain a key, only placeholders in the auth headers" do
      keys = MealSuggesterHelpers::TEST_KEYS.values + VcrKeys::ENV_KEYS.filter_map { |name| ENV[name].presence }
      real_looking = [ /AIza[0-9A-Za-z_-]{30,}/, /sk-ant-[0-9A-Za-z_-]{20,}/, /sk-(proj-)?[0-9A-Za-z_-]{20,}/ ]

      files.each do |file|
        text = file.read
        keys.each { |key| expect(text).not_to include(key), "#{file} contains a key" }
        real_looking.each { |pattern| expect(text).not_to match(pattern), "#{file} contains something key-shaped" }

        headers = YAML.safe_load(text).fetch("http_interactions").map { |interaction| interaction.dig("request", "headers") }
        auth = headers.flat_map { |h| h.slice("Authorization", "X-Api-Key", "X-Goog-Api-Key").values.flatten }
        expect(auth).to all(match(/\A(Bearer )?<[A-Z_]+>\z/))
        expect(auth).not_to be_empty
      end
    end

    it "never contain a patient name" do
      files.each { |file| expect(file.read).not_to match(/\b(ann|lee|bertram)\b/i), "#{file} contains a name" }
    end
  end
end
