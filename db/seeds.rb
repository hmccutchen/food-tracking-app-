# The app has exactly one user: the nurse.
# Development and test fall back to a throwaway login; anywhere else the
# password must be given, so no deployed app ever has a known default.
email = ENV.fetch("NURSE_EMAIL", "nurse@example.com")
password = Rails.env.local? ? ENV.fetch("NURSE_PASSWORD", "change-me-please") : ENV["NURSE_PASSWORD"]

if password.present?
  User.find_or_create_by!(email_address: email) do |user|
    user.password = password
  end
elsif !User.exists?(email_address: email)
  warn "Skipping the nurse account: set NURSE_PASSWORD (and NURSE_EMAIL) and run db:seed again."
end

Taxonomy::Seed.load!

require Rails.root.join("db/seeds/prep_methods").to_s
PrepMethodSeedData.load!

# One line for deploy logs: counts and yes/no only, never names or secrets.
puts "Seeded: #{TaxonomyNode.count} taxonomy nodes, #{PrepMethod.count} prep methods, " \
  "#{IngredientDescriptor.count} descriptor words; nurse account #{User.exists?(email_address: email) ? 'present' : 'MISSING'}"
