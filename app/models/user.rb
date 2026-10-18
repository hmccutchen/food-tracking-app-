class User < ApplicationRecord
  # No sign-up, reset emails or lockout: one nurse, created by db/seeds.rb.
  # Devise strips and downcases the email (config.case_insensitive_keys).
  devise :database_authenticatable, :rememberable, :validatable

  has_many :patients, dependent: :destroy
  has_many :restrictions, through: :patients
  has_many :provider_credentials, dependent: :delete_all
  has_many :meal_requests, dependent: :destroy
  # Taxonomy nodes she added herself (CustomItem). Kept if she is ever removed,
  # so the restrictions and checks that rely on them don't silently change.
  has_many :custom_items, -> { custom }, class_name: "TaxonomyNode", foreign_key: :created_by_id,
    inverse_of: :created_by, dependent: :nullify

  validates :active_provider, inclusion: { in: Ai::Providers.keys }, allow_nil: true
  # bcrypt ignores everything past 72 bytes, and Devise's password_length
  # counts characters: 18 emoji fill those bytes on their own.
  validate :password_fits_bcrypt, if: -> { password.present? }

  # A new password signs out the nurse's other devices (Devise checks the password
  # salt on every request); cut those devices' meal-update sockets too.
  after_update_commit :disconnect_cable_connections, if: :saved_change_to_encrypted_password?

  # The credential for the provider the nurse picked, or nil.
  def active_credential
    provider_credentials.find_by(provider: active_provider) if active_provider.present?
  end

  private

  def disconnect_cable_connections
    ActionCable.server.remote_connections.where(current_user: self).disconnect(reconnect: false)
  end

  def password_fits_bcrypt
    errors.add(:password, "is too long (maximum is 72 bytes; some characters take up to 4)") if password.bytesize > 72
  end
end
