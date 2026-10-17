# Keys come from the environment in production. Development, test and asset builds use fixed,
# non-secret keys so the app runs without credentials.
dev_keys = {
  primary_key: "dev-primary-key-not-secret-000000",
  deterministic_key: "dev-deterministic-key-not-secret0",
  key_derivation_salt: "dev-key-derivation-salt-not-secret"
}

Rails.application.configure do
  encryption = config.active_record.encryption
  # SECRET_KEY_BASE_DUMMY marks a build step (assets:precompile in the
  # Dockerfile) that boots production without secrets and never touches data,
  # so it gets the throwaway keys. Real keys stay runtime-only.
  if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
    encryption.primary_key = ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY")
    encryption.deterministic_key = ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY")
    encryption.key_derivation_salt = ENV.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT")
  else
    encryption.primary_key = dev_keys[:primary_key]
    encryption.deterministic_key = dev_keys[:deterministic_key]
    encryption.key_derivation_salt = dev_keys[:key_derivation_salt]
  end
end
