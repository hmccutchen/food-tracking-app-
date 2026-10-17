module Ai
  # Background jobs must take a user_id only, never an API key or a
  # credential's attributes: job arguments are serialized into the queue
  # table and logs. A job calls this at run time to load the key.
  module CredentialLookup
    # The user's active provider credential, or nil if none is set up.
    def self.for(user_id)
      User.find(user_id).active_credential
    end
  end
end
