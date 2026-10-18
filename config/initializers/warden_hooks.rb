# A tab that subscribed to meal broadcasts must stop receiving them once the
# nurse signs out. This drops all of the account's sockets; tabs on devices that are
# still signed in reconnect on their own.
Warden::Manager.before_logout do |user, _auth, _opts|
  ActionCable.server.remote_connections.where(current_user: user).disconnect if user
end
