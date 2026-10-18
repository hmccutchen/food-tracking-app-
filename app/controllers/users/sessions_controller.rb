module Users
  class SessionsController < Devise::SessionsController
    rate_limit to: 10, within: 3.minutes, only: :create,
      with: -> { redirect_to new_user_session_path, alert: "Too many attempts. Try again in a few minutes." }
  end
end
