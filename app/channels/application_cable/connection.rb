module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # Sign-out and a password change disconnect the user's sockets (see
    # config/initializers/warden_hooks.rb and User); a reconnect from a browser
    # that is no longer signed in is then rejected here.
    identified_by :current_user

    def connect
      self.current_user = env["warden"]&.user(:user) || reject_unauthorized_connection
    end
  end
end
