# The app has exactly one user: the nurse.
email = ENV.fetch("NURSE_EMAIL", "nurse@example.com")
password = ENV.fetch("NURSE_PASSWORD", "change-me-please")

User.find_or_create_by!(email_address: email) do |user|
  user.password = password
end

Taxonomy::Seed.load!
