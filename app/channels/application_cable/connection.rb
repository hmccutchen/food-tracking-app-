module ApplicationCable
  class Connection < ActionCable::Connection::Base
    # Identified by session as well as user, so ending a session (sign-out,
    # password reset) can cut off exactly the sockets it opened. See Session.
    identified_by :current_user, :current_session

    def connect
      set_current_user || reject_unauthorized_connection
    end

    private
      def set_current_user
        if session = Session.find_by(id: cookies.signed[:session_id])
          self.current_session = session
          self.current_user = session.user
        end
      end
  end
end
