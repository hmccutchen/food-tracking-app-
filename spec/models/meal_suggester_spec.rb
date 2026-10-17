require "rails_helper"

RSpec.describe MealSuggester do
  # Stands in for an Ai::Adapters class: records the prompt, returns canned text.
  let(:fake_adapter) do
    Class.new do
      attr_reader :prompt

      def initialize(reply) = @reply = reply

      def complete(prompt)
        @prompt = prompt
        @reply
      end
    end
  end

  let(:reply) { { meals: [ { dish: "Lentil soup", ingredients: [ "red lentils", "carrot" ], prep_notes: [] } ] }.to_json }
  let(:adapter) { fake_adapter.new(reply) }
  let(:credential) { adapter_credential("anthropic") }

  it "returns a Result of Suggestions" do
    result = described_class.new(credential, adapter:).suggest(terms: [ "milk" ], request: "soup")
    expect(result).to be_a(MealSuggester::Result)
    expect(result.suggestions).to eq([ MealSuggester::Suggestion.new(dish: "Lentil soup", ingredients: [ "red lentils", "carrot" ], prep_notes: []) ])
  end

  it "builds the prompt from terms, the redacted request and rejected ingredients" do
    described_class.new(credential, adapter:).suggest(**sample_suggest_args, count: 2)
    expect(adapter.prompt.terms).to eq([ "milk", "peanut", "sodium" ])
    expect(adapter.prompt.rejected).to eq([ "butter" ])
    expect(adapter.prompt.count).to eq(2)
    expect(adapter.prompt.request).to eq("Warm dinner for the patient and the patient, something soft. the patient likes fish.")
    expect(adapter.prompt.text).not_to match(/ann|lee|bertram/i)
  end

  it "raises a malformed-response error the caller can count as a failed attempt" do
    expect { described_class.new(credential, adapter: fake_adapter.new("Sorry, no.")).suggest(terms: [], request: "") }
      .to raise_error(Ai::MalformedResponseError, "Anthropic Claude sent back something we couldn't read. Trying again may help.")
  end

  it "picks the adapter from the credential's provider" do
    {
      "gemini" => Ai::Adapters::Gemini, "anthropic" => Ai::Adapters::Anthropic, "openai" => Ai::Adapters::OpenAI
    }.each do |provider, klass|
      expect(Ai::Adapters.for(adapter_credential(provider))).to be_a(klass)
    end
  end

  it "never shows the key when inspected" do
    adapter = Ai::Adapters.for(credential)
    expect(adapter.inspect).not_to include(credential.api_key)
  end
end
