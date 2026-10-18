class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Signed-in pages carry patient names and restriction terms. Keep them out of
  # the browser's HTTP cache; the service worker's own expiring cache is the
  # only place they may be saved.
  after_action :no_store, if: :authenticated?
end
