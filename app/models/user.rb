class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :patients, dependent: :destroy
  has_many :provider_credentials, dependent: :delete_all

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :active_provider, inclusion: { in: Ai::Providers.keys }, allow_nil: true

  # The credential for the provider the nurse picked, or nil.
  def active_credential
    provider_credentials.find_by(provider: active_provider) if active_provider.present?
  end
end
