# A tab that subscribed to meal broadcasts must stop receiving them once the
# nurse signs out. The sign-out response clears the cookie only when it
# arrives, so a tab told to reconnect could get back in with the old cookie
# first; reconnect: false keeps it closed. Pages open on other signed-in
# devices pick live updates up again on their next page visit.
Warden::Manager.before_logout do |user, _auth, _opts|
  ActionCable.server.remote_connections.where(current_user: user).disconnect(reconnect: false) if user
end
