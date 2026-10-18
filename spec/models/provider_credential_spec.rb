require "rails_helper"

RSpec.describe ProviderCredential do
  subject(:credential) { build(:provider_credential) }

  it { is_expected.to belong_to(:user) }
  it { is_expected.to validate_presence_of(:api_key) }
  it { is_expected.to validate_uniqueness_of(:provider).scoped_to(:user_id).ignoring_case_sensitivity }

  it "only allows the known providers" do
    credential.provider = "acme"
    expect(credential).not_to be_valid
  end

  describe "encryption at rest" do
    def raw_key(id) = ActiveRecord::Base.connection.select_value("SELECT api_key FROM provider_credentials WHERE id = #{id.to_i}")

    it "never stores the key in plain text, and encrypts non-deterministically" do
      key = "sk-plain-text-check-1234"
      one = create(:provider_credential, api_key: key)
      two = create(:provider_credential, api_key: key)
      expect(raw_key(one.id)).not_to include(key)
      expect(raw_key(one.id)).not_to eq(raw_key(two.id))
      expect(one.reload.api_key).to eq(key)
    end
  end

  describe "#replace_key" do
    let(:credential) { create(:provider_credential, provider: "anthropic", api_key: "old-key-0000") }

    it "stores the key, last 4, models and check time when the provider accepts it" do
      stub_models_success("anthropic")
      credential.replace_key("  new-key-9876 ")
      credential.save!
      credential.reload
      expect(credential).to have_attributes(api_key: "new-key-9876", key_last4: "9876",
        available_models: %w[model-a model-b], last_error_code: nil)
      expect(credential.validated_at).to be_within(5.seconds).of(Time.current)
    end

    it "keeps the previous key when the provider rejects the new one" do
      stub_models_failure("anthropic", status: 401)
      expect { credential.replace_key("bad-key-1111") }.to raise_error(Ai::InvalidKeyError)
      expect(credential).to have_attributes(api_key: "old-key-0000", key_last4: "0000")
    end
  end

  describe "#check!" do
    let(:credential) { create(:provider_credential, provider: "gemini", available_models: []) }

    it "refreshes the model list on success" do
      stub_models_success("gemini")
      expect(credential.check!).to be_nil
      expect(credential.reload.available_models).to eq(%w[model-a model-b])
    end

    it "records the error code and keeps the key on failure" do
      stub_models_failure("gemini", status: 500)
      error = credential.check!
      expect(error).to be_a(Ai::ProviderError)
      expect(credential.reload.last_error).to be_a(Ai::ProviderError)
      expect(credential.api_key).to be_present
    end
  end

  describe "#choose_model" do
    it "prefers the free-text model id over the picked one" do
      credential.choose_model("model-a", " custom-model ")
      expect(credential.model).to eq("custom-model")
      credential.choose_model("model-a", "")
      expect(credential.model).to eq("model-a")
    end
  end
end
