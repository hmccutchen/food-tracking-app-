require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) }

  def warden_for(signed_in_user)
    instance_double(Warden::Proxy).tap { |warden| allow(warden).to receive(:user).with(:user).and_return(signed_in_user) }
  end

  it "identifies the connection by the signed-in user" do
    connect "/cable", env: { "warden" => warden_for(user) }
    expect(connection.current_user).to eq(user)
  end

  it "rejects a connection from a browser that is not signed in" do
    expect { connect "/cable", env: { "warden" => warden_for(nil) } }.to have_rejected_connection
  end
end

RSpec.describe "Ending a sign-in cuts open sockets" do
  let(:user) { create(:user) }
  let(:remote) { instance_double(ActionCable::RemoteConnections::RemoteConnection, disconnect: nil) }
  let(:connections) { instance_double(ActionCable::RemoteConnections, where: remote) }

  before { allow(ActionCable.server).to receive(:remote_connections).and_return(connections) }

  it "disconnects the user's sockets on sign-out", type: :request do
    sign_in(user)
    sign_out
    expect(connections).to have_received(:where).with(current_user: user)
    expect(remote).to have_received(:disconnect)
  end

  it "disconnects the user's sockets when the password changes" do
    user.update!(password: "a-brand-new-password")
    expect(connections).to have_received(:where).with(current_user: user)
    expect(remote).to have_received(:disconnect)
  end

  it "leaves sockets alone for other updates" do
    user.update!(offline_caching_enabled: false)
    expect(connections).not_to have_received(:where)
  end
end
