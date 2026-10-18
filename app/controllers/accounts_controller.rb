# The nurse's own account: change the password. Needs the current one.
class AccountsController < ApplicationController
  def edit
  end

  def update
    # Devise skips a blank new password and reports success; it must not here.
    if password_params[:password].blank?
      current_user.errors.add(:password, :blank)
      render :edit, status: :unprocessable_content
    elsif current_user.update_with_password(password_params)
      # The password salt changed, so re-sign this browser; others are signed out.
      bypass_sign_in current_user
      redirect_to edit_account_path, notice: "Password changed. Other devices have been signed out."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def password_params
    params.expect(user: %i[current_password password password_confirmation])
  end
end
