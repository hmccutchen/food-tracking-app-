require "rails_helper"

RSpec.describe "Home" do
  it "redirects signed-out visitors to sign in" do
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "shows the home page once signed in" do
    user = create(:user)
    sign_in(user)
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(user.email_address)
  end
end
