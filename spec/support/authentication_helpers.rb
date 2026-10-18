module AuthenticationHelpers
  # Both sign in through the real form, so specs exercise Devise end to end.
  module Request
    def sign_in(user, password: "correct-horse-battery")
      post user_session_path, params: { user: { email: user.email, password: password } }
    end

    def sign_out
      delete destroy_user_session_path
    end
  end

  module System
    def sign_in(user, password: "correct-horse-battery")
      visit new_user_session_path
      fill_in "Email address", with: user.email
      fill_in "Password", with: password
      click_button "Sign in"
    end
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers::Request, type: :request
  config.include AuthenticationHelpers::System, type: :system
end
