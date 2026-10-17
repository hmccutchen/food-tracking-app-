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
end
