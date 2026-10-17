require "rails_helper"

RSpec.describe "Home" do
  it "redirects signed-out visitors to sign in" do
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "sends the signed-in nurse to her patients" do
    user = create(:user)
    sign_in(user)
    get root_path
    expect(response).to redirect_to(patients_path)
    follow_redirect!
    expect(response.body).to include(user.email_address)
  end
end
