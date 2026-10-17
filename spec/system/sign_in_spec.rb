require "rails_helper"

RSpec.describe "Signing in" do
  it "lets the nurse sign in and out" do
    user = create(:user)
    sign_in(user)
    expect(page).to have_content("Signed in as #{user.email_address}")

    click_button "Sign out"
    expect(page).to have_current_path(new_session_path)
  end
end
