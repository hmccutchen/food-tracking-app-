class Session < ApplicationRecord
  belongs_to :user

  # A tab that subscribed to meal broadcasts before this session ended must
  # stop receiving them. Covers sign-out and password reset (which destroys
  # every session of the user); the reconnect is then rejected.
  after_destroy_commit :disconnect_cable_connections

  private

  def disconnect_cable_connections
    ActionCable.server.remote_connections.where(current_user: user, current_session: self).disconnect
  end
end
