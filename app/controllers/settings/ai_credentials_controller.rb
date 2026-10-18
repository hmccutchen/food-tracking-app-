module Settings
  # Saves and tests one provider's key and model. Always scoped to Current.user.
  # The key is never echoed back: not in the form, flash, or errors.
  class AiCredentialsController < ApplicationController
    before_action :set_provider

    def update
      @credential = Current.user.provider_credentials.find_or_initialize_by(provider: @provider.key)
      @credential.choose_model(credential_params[:model], credential_params[:other_model])
      error = replace_key_if_given

      if @credential.api_key.blank?
        render_card_error(error&.plain_message || "Add your #{@provider.name} key first.")
      elsif !@credential.save
        render_card_error(@credential.errors.full_messages.to_sentence)
      elsif error
        # Other settings were saved; the new key was not.
        render_card_error("#{error.plain_message} Your saved key was kept.")
      else
        redirect_to settings_ai_path, notice: "#{@provider.name} settings saved (key ending in #{@credential.key_last4})."
      end
    end

    def test
      credential = Current.user.provider_credentials.find_by!(provider: @provider.key)
      if (error = credential.check!)
        redirect_to settings_ai_path, alert: error.plain_message
      else
        redirect_to settings_ai_path, notice: "Your #{@provider.name} key works."
      end
    end

    private

    def set_provider
      @provider = Ai::Providers::ALL[params[:provider].to_s] or raise ActiveRecord::RecordNotFound
    end

    def credential_params
      params.fetch(:provider_credential, {}).permit(:api_key, :model, :other_model)
    end

    def replace_key_if_given
      return if credential_params[:api_key].blank?

      @credential.replace_key(credential_params[:api_key])
      nil
    rescue Ai::Error => e
      e
    end

    def render_card_error(message)
      @credentials = Current.user.provider_credentials.index_by(&:provider)
      @credentials[@provider.key] = @credential if @credential.persisted?
      @card_errors = { @provider.key => message }
      render "settings/ai/show", status: :unprocessable_content
    end
  end
end
