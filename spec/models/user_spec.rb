require "rails_helper"

RSpec.describe User do
  it "normalizes the email address" do
    user = create(:user, email: "  Nurse@Example.COM ")
    expect(user.email).to eq("nurse@example.com")
  end

  it "checks the password" do
    user = create(:user)
    expect(user.valid_password?("correct-horse-battery")).to be(true)
    expect(user.valid_password?("wrong")).to be(false)
  end

  it "keeps working with a password hashed before the move to Devise" do
    user = create(:user)
    user.update_column(:encrypted_password, BCrypt::Password.create("hashed-by-has-secure-password", cost: BCrypt::Engine::MIN_COST))
    expect(user.reload.valid_password?("hashed-by-has-secure-password")).to be(true)
  end

  it "needs a password of 12 to 72 characters" do
    expect(build(:user, password: "a" * 11)).not_to be_valid
    expect(build(:user, password: "a" * 12)).to be_valid
    expect(build(:user, password: "a" * 73)).not_to be_valid
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
