require "rails_helper"

RSpec.describe Ai::CredentialLookup do
  it "loads the user's active credential by user id at run time" do
    user = create(:user, active_provider: "anthropic")
    create(:provider_credential, user: user, provider: "openai")
    anthropic = create(:provider_credential, user: user, provider: "anthropic")
    expect(described_class.for(user.id)).to eq(anthropic)
  end

  it "returns nil when no provider is chosen" do
    expect(described_class.for(create(:user).id)).to be_nil
  end
end
