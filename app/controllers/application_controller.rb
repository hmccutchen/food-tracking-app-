class ApplicationController < ActionController::Base
  # Every page needs the nurse signed in; only Devise's sign-in page is open.
  before_action :authenticate_user!
  before_action { Current.user = current_user }

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Signed-in pages carry patient names and restriction terms. Keep them out of
  # the browser's HTTP cache; the service worker's own expiring cache is the
  # only place they may be saved.
  after_action :no_store, if: :user_signed_in?
end
