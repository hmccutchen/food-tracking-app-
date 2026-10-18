require "zlib"

# The service worker's app-shell list: compiled CSS and JS (digested paths),
# icons and the offline page. Static assets only, never a page with user data.
module PwaHelper
  OFFLINE_PAGE = "/offline.html".freeze
  ICONS = %w[/icon-192.png /icon-512.png].freeze

  def pwa_shell_urls
    stylesheets = app_stylesheets_paths.map { |path| asset_path(path) }
    scripts = JSON.parse(Rails.application.importmap.to_json(resolver: self)).fetch("imports").values
    (stylesheets + scripts + ICONS + [ OFFLINE_PAGE ]).uniq
  end

  # Changes whenever an asset digest changes, so a new deploy gets a fresh
  # app-shell-v<N> cache and the old one is deleted on activate.
  def pwa_shell_version
    Zlib.crc32(pwa_shell_urls.join("\n"))
  end
end
