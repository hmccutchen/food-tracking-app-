require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) }
  let(:session) { user.sessions.create! }

  it "identifies the connection by its session as well as its user" do
    cookies.signed[:session_id] = session.id
    connect "/cable"
    expect(connection.current_user).to eq(user)
    expect(connection.current_session).to eq(session)
  end

  it "rejects a connection whose session has ended" do
    cookies.signed[:session_id] = session.id
    session.destroy
    expect { connect "/cable" }.to have_rejected_connection
  end
end

RSpec.describe Session do
  let(:user) { create(:user) }

  it "disconnects that session's sockets when it is destroyed (sign-out)" do
    session = user.sessions.create!
    remote = instance_double(ActionCable::RemoteConnections::RemoteConnection, disconnect: nil)
    connections = instance_double(ActionCable::RemoteConnections)
    allow(ActionCable.server).to receive(:remote_connections).and_return(connections)
    allow(connections).to receive(:where).and_return(remote)

    session.destroy

    expect(connections).to have_received(:where).with(current_user: user, current_session: session)
    expect(remote).to have_received(:disconnect)
  end

  it "disconnects every session's sockets on a password reset (destroy_all)" do
    sessions = Array.new(2) { user.sessions.create! }
    remote = instance_double(ActionCable::RemoteConnections::RemoteConnection, disconnect: nil)
    connections = instance_double(ActionCable::RemoteConnections, where: remote)
    allow(ActionCable.server).to receive(:remote_connections).and_return(connections)

    user.sessions.destroy_all

    sessions.each { |session| expect(connections).to have_received(:where).with(current_user: user, current_session: session) }
  end
end
