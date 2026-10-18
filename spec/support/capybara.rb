require "capybara/cuprite"

# Named :chromium because Rails' driven_by re-registers :cuprite with its own options.
Capybara.register_driver(:chromium) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    browser_path: ENV.fetch("BROWSER_PATH", "/opt/pw-browsers/chromium-1194/chrome-linux/chrome"),
    browser_options: { "no-sandbox" => nil },
    headless: true,
    window_size: [ 1200, 900 ]
  )
end

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :rack_test }
  config.before(:each, type: :system, js: true) { driven_by :chromium }
end
