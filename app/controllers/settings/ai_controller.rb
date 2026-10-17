module Settings
  # /settings/ai: the nurse's provider choice and one card per provider.
  class AiController < ApplicationController
    def show
      @credentials = Current.user.provider_credentials.index_by(&:provider)
    end

    # Picks the active provider. Never calls the provider, so it works even
    # when one is down.
    def update
      choice = params[:active_provider].presence
      if Current.user.update(active_provider: choice)
        message = choice ? "#{Ai::Providers.name_for(choice)} will be used for meal ideas." : "No AI provider chosen."
        redirect_to settings_ai_path, notice: message
      else
        @credentials = Current.user.provider_credentials.index_by(&:provider)
        flash.now[:alert] = "Pick one of the listed providers."
        render :show, status: :unprocessable_content
      end
    end
  end
end
