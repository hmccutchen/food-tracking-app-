module AuthenticationHelpers
  module Request
    def sign_in(user, password: "password123")
      post session_path, params: { email_address: user.email_address, password: password }
    end
  end

  module System
    def sign_in(user, password: "password123")
      visit new_session_path
      fill_in "email_address", with: user.email_address
      fill_in "password", with: password
      click_button "Sign in"
    end
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers::Request, type: :request
  config.include AuthenticationHelpers::System, type: :system
end
