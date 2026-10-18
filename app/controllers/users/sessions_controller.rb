module Users
  class SessionsController < Devise::SessionsController
    # Prepended so it runs before Devise's callbacks and ApplicationController's
    # current_user lookup, either of which would otherwise check the submitted
    # password (and could sign in) before an over-limit request is turned away.
    rate_limit to: 10, within: 3.minutes, only: :create, prepend: true,
      with: -> { redirect_to new_user_session_path, alert: "Too many attempts. Try again in a few minutes." }
  end
end
