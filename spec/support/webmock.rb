require "webmock/rspec"

# No spec may reach the network. Recorded responses (VCR) are the only way in.
WebMock.disable_net_connect!(allow_localhost: true)
