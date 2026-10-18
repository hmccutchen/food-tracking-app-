module Settings
  # /settings/offline: whether this device may keep saved avoid lists.
  # The page load after saving tells the service worker the new choice; when
  # it is off, the worker deletes the avoid-lists cache straight away.
  class OfflineController < ApplicationController
    def show
    end

    def update
      enabled = ActiveModel::Type::Boolean.new.cast(params.dig(:user, :offline_caching_enabled)) || false
      Current.user.update!(offline_caching_enabled: enabled)
      message = enabled ? "Avoid lists will be saved for offline use." : "Offline saving is off. Saved avoid lists were deleted."
      redirect_to settings_offline_path, notice: message
    end
  end
end
