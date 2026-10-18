require "rails_helper"

RSpec.describe "Signing in" do
  let(:user) { create(:user) }

  it "signs in with the right password and out again" do
    sign_in(user)
    expect(response).to redirect_to(root_path)

    sign_out
    expect(response).to redirect_to(root_path)
    get patients_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "rejects a wrong password without saying whether the email exists" do
    sign_in(user, password: "not-the-password")
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Invalid email or password.")

    post user_session_path, params: { user: { email: "nobody@example.com", password: "not-the-password" } }
    expect(response.body).to include("Invalid email or password.")
  end

  it "stops checking passwords after 10 attempts in 3 minutes, even a right one" do
    10.times { sign_in(user, password: "not-the-password") }
    expect(response).to have_http_status(:unprocessable_content)

    sign_in(user)
    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq("Too many attempts. Try again in a few minutes.")
    get patients_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "has no sign-up or password-reset pages" do
    expect(Rails.application.routes.url_helpers).not_to respond_to(:new_user_registration_path)
    expect(Rails.application.routes.url_helpers).not_to respond_to(:new_user_password_path)
  end

  it "shows the sign-in form with keep-me-signed-in on" do
    get new_user_session_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Keep me signed in on this device")
  end
end
