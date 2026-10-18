require "rails_helper"

RSpec.describe "AI settings" do
  let(:user) { create(:user) }
  let(:full_key) { "sk-proj-VERYSECRETabcdef0123456789-4321" }

  before { sign_in(user) }

  def capture_log
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(logger)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  def save_key(provider, key, **extra)
    patch settings_ai_credential_path(provider), params: { provider_credential: { api_key: key, **extra } }
  end

  it "requires sign-in" do
    delete session_path
    get settings_ai_path
    expect(response).to redirect_to(new_session_path)
  end

  it "shows the privacy note, a card per provider and the nav link" do
    get settings_ai_path
    expect(response.body).to include(
      "Only restriction terms (like 'tree nut' or 'low sodium') are sent to the provider you choose — never patient names.",
      "Google Gemini", "Anthropic Claude", "OpenAI", %(href="#{settings_ai_path}">AI settings</a>)
    )
  end

  describe "saving a key" do
    it "validates, stores the key and models, and shows only the last 4" do
      stub_models_success("openai")
      save_key("openai", full_key)
      expect(response).to redirect_to(settings_ai_path)

      credential = user.provider_credentials.find_by!(provider: "openai")
      expect(credential).to have_attributes(api_key: full_key, key_last4: "4321", available_models: %w[model-a model-b])

      follow_redirect!
      expect(response.body).to include("Saved key ending in 4321", "Leave blank to keep the saved key", "Checked less than a minute ago")
      expect(response.body).to include(%(<option value="model-a">model-a</option>))
      expect(response.body).not_to include(full_key)
    end

    it "stores nothing and says why when the provider rejects a first key" do
      stub_models_failure("gemini", status: 400, body: { error: { details: [ { reason: "API_KEY_INVALID" } ] } })
      save_key("gemini", full_key)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("That key wasn&#39;t accepted. Check you copied the whole key for Google Gemini.")
      expect(response.body).not_to include(full_key)
      expect(user.provider_credentials).to be_empty
    end

    it "keeps AI settings marked as the current section on the error page" do
      stub_models_failure("gemini", status: 400, body: { error: { details: [ { reason: "API_KEY_INVALID" } ] } })
      save_key("gemini", full_key)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(%(aria-current="true" href="#{settings_ai_path}">AI settings</a>))
      expect(response.body).to match(/data-current\s*>More</)
    end

    it "keeps the previous key when a replacement fails, but still saves the model" do
      credential = create(:provider_credential, user: user, provider: "anthropic", api_key: "old-key-0000")
      stub_models_failure("anthropic", status: 429, body: { error: { type: "rate_limit_error" } })
      save_key("anthropic", full_key, model: "model-b")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Anthropic Claude is busy right now (rate limit).", "Your saved key was kept.")
      expect(response.body).not_to include(full_key)
      expect(credential.reload).to have_attributes(api_key: "old-key-0000", key_last4: "0000", model: "model-b")
    end

    it "changes the model without calling the provider when the key is left blank" do
      credential = create(:provider_credential, user: user, provider: "openai")
      save_key("openai", "", model: "model-a", other_model: "brand-new-model")
      expect(response).to redirect_to(settings_ai_path)
      expect(credential.reload.model).to eq("brand-new-model")

      follow_redirect!
      expect(response.body).to include(%(value="brand-new-model"))
    end

    it "asks for a key before saving a model for a new provider" do
      save_key("openai", "", model: "model-a")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Add your OpenAI key first.")
    end

    it "rejects an unknown provider" do
      save_key("acme", full_key)
      expect(response).to have_http_status(:not_found)
    end

    it "never writes the key to the log" do
      stub_models_success("openai")
      log = capture_log { save_key("openai", full_key) }
      expect(log).to include("Settings::AiCredentialsController#update", "[FILTERED]")
      expect(log).not_to include(full_key)

      stub_models_failure("openai", status: 401)
      log = capture_log { save_key("openai", "#{full_key}-replacement") }
      expect(log).not_to include(full_key)
    end
  end

  describe "Test key" do
    let!(:credential) { create(:provider_credential, user: user, provider: "openai", available_models: []) }

    it "re-validates the saved key and refreshes the models" do
      stub_models_success("openai")
      post test_settings_ai_credential_path("openai")
      expect(response).to redirect_to(settings_ai_path)
      expect(flash[:notice]).to eq("Your OpenAI key works.")
      expect(credential.reload.available_models).to eq(%w[model-a model-b])
    end

    it "shows the failure in plain words on the card" do
      stub_models_failure("openai", status: 429, body: { error: { code: "insufficient_quota" } })
      post test_settings_ai_credential_path("openai")
      follow_redirect!
      expect(response.body).to include("Your OpenAI account is out of credit or over its quota.")
      expect(response.body).to include("Last check less than a minute ago")
      expect(response.body).not_to include(credential.api_key)
    end

    it "only tests the signed-in nurse's own key" do
      create(:provider_credential, provider: "gemini") # another nurse's
      post test_settings_ai_credential_path("gemini")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "picking the provider" do
    it "sets and clears the active provider, without calling any provider" do
      patch settings_ai_path, params: { active_provider: "anthropic" }
      expect(response).to redirect_to(settings_ai_path)
      expect(user.reload.active_provider).to eq("anthropic")

      patch settings_ai_path, params: { active_provider: "" }
      expect(user.reload.active_provider).to be_nil
    end

    it "rejects an unknown provider" do
      patch settings_ai_path, params: { active_provider: "acme" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.active_provider).to be_nil
    end
  end

  it "only shows the signed-in nurse's keys" do
    create(:provider_credential, provider: "openai", api_key: "someone-elses-key-7777")
    get settings_ai_path
    expect(response.body).not_to include("7777")
  end
end
