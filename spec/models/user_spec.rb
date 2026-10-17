require "rails_helper"

RSpec.describe User do
  it "normalizes the email address" do
    user = create(:user, email_address: "  Nurse@Example.COM ")
    expect(user.email_address).to eq("nurse@example.com")
  end

  it "authenticates with the right password only" do
    user = create(:user)
    expect(User.authenticate_by(email_address: user.email_address, password: "password123")).to eq(user)
    expect(User.authenticate_by(email_address: user.email_address, password: "wrong")).to be_nil
  end

  it "only accepts a known active provider" do
    expect(build(:user, active_provider: "acme")).not_to be_valid
    expect(build(:user, active_provider: "gemini")).to be_valid
    expect(build(:user, active_provider: nil)).to be_valid
  end

  it "finds the credential for its active provider" do
    user = create(:user, active_provider: "openai")
    credential = create(:provider_credential, user: user, provider: "openai")
    create(:provider_credential, provider: "openai") # someone else's
    expect(user.active_credential).to eq(credential)
    user.update!(active_provider: "gemini")
    expect(user.active_credential).to be_nil
  end
end
