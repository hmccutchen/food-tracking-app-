# One nurse's API key for one AI provider. The key is encrypted at rest,
# filtered from logs, and only its last four characters are ever shown.
class ProviderCredential < ApplicationRecord
  belongs_to :user

  encrypts :api_key

  enum :provider, Ai::Providers.keys.index_with(&:itself), validate: true

  validates :api_key, :key_last4, presence: true
  validates :provider, uniqueness: { scope: :user_id }

  def provider_name = Ai::Providers.fetch(provider).name

  # Checks new_key with the provider and keeps it only if accepted. On
  # failure raises Ai::Error and leaves the saved key untouched.
  def replace_key(new_key)
    key = new_key.to_s.strip
    models = Ai::KeyValidator.call(provider, key)
    self.api_key = key
    self.key_last4 = key.last(4)
    record_success(models)
  end

  # Re-checks the saved key ("Test key"). Returns nil or the Ai::Error.
  def check!
    record_success(Ai::KeyValidator.call(provider, api_key))
    save!
    nil
  rescue Ai::Error => e
    update!(last_error_code: e.code, last_checked_at: Time.current)
    e
  end

  # A picked model, or a free-text model id (which wins: lists change).
  def choose_model(choice, other)
    self.model = other.to_s.strip.presence || choice.to_s.strip.presence
  end

  # The error from the most recent check, if that check failed.
  def last_error
    Ai::Error.from_code(last_error_code, provider) if last_error_code.present?
  end

  private

  def record_success(models)
    now = Time.current
    self.available_models = models
    self.validated_at = now
    self.last_checked_at = now
    self.last_error_code = nil
  end
end
