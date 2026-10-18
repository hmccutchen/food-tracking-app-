# The app has exactly one user: the nurse.
# Development and test fall back to a throwaway login; anywhere else the
# password must be given, so no deployed app ever has a known default.
#
# NURSE_PASSWORD only sets the password when the account is first created;
# after that the nurse changes it on the Account page. To reset a forgotten
# password, set NURSE_PASSWORD to a new value plus NURSE_RESET_PASSWORD=1,
# deploy once, then remove NURSE_RESET_PASSWORD.
module NurseSeed
  def self.email(env = ENV)
    env.fetch("NURSE_EMAIL", "nurse@example.com").strip.downcase
  end

  def self.load!(env: ENV, local: Rails.env.local?)
    password = local ? env.fetch("NURSE_PASSWORD", "change-me-please") : env["NURSE_PASSWORD"]
    if password.blank?
      warn "Skipping the nurse account: set NURSE_PASSWORD (and NURSE_EMAIL) and run db:seed again." unless User.exists?(email: email(env))
      return
    end

    nurse = User.find_or_initialize_by(email: email(env))
    if nurse.new_record?
      nurse.update!(password: password)
    elsif env["NURSE_RESET_PASSWORD"] == "1"
      nurse.update!(password: password)
      puts "Nurse password reset from NURSE_PASSWORD; remove NURSE_RESET_PASSWORD now."
    end
  end
end
