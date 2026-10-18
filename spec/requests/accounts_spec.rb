require "rails_helper"

RSpec.describe "Account" do
  let(:user) { create(:user) }

  def change_password(current:, new:, confirmation: new)
    patch account_path, params: { user: { current_password: current, password: new, password_confirmation: confirmation } }
  end

  it "requires sign-in" do
    get edit_account_path
    expect(response).to redirect_to(new_user_session_path)
  end

  context "when signed in" do
    before { sign_in(user) }

    it "is linked from the More menu" do
      get edit_account_path
      expect(response.body).to include(%(aria-current="page" href="#{edit_account_path}">Account</a>), "Signed in as #{user.email}")
    end

    it "changes the password and keeps this browser signed in" do
      change_password(current: "correct-horse-battery", new: "a-brand-new-password")
      expect(response).to redirect_to(edit_account_path)
      expect(user.reload.valid_password?("a-brand-new-password")).to be(true)

      follow_redirect!
      expect(response.body).to include("Password changed. Other devices have been signed out.")
    end

    it "needs the current password" do
      change_password(current: "wrong-current-password", new: "a-brand-new-password")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Current password is invalid")
      expect(user.reload.valid_password?("correct-horse-battery")).to be(true)
    end

    it "refuses a blank, short or mismatched new password" do
      change_password(current: "correct-horse-battery", new: "")
      expect(response.body).to include("Password can&#39;t be blank")
      change_password(current: "correct-horse-battery", new: "too-short")
      expect(response.body).to include("Password is too short (minimum is 12 characters)")
      change_password(current: "correct-horse-battery", new: "a-brand-new-password", confirmation: "something-else")
      expect(response.body).to include("Password confirmation doesn&#39;t match Password")
      expect(user.reload.valid_password?("correct-horse-battery")).to be(true)
    end
  end

  it "signs out other browsers when the password changes" do
    sign_in(user)
    other = ActionDispatch::Integration::Session.new(Rails.application) # a second browser
    other.post user_session_path, params: { user: { email: user.email, password: "correct-horse-battery" } }
    other.get patients_path
    expect(other.response).to have_http_status(:ok)

    change_password(current: "correct-horse-battery", new: "a-brand-new-password")
    other.get patients_path
    # (redirect_to would check this example's own response, not other's.)
    expect(other.response).to have_http_status(:found)
    expect(URI(other.response.location).path).to eq(new_user_session_path)
    get patients_path
    expect(response).to have_http_status(:ok)
  end
end
