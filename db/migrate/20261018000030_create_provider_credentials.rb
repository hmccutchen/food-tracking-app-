class CreateProviderCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :provider_credentials do |t|
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      # Encrypted with Active Record Encryption (non-deterministic). Never rendered or logged.
      t.text :api_key, null: false
      t.string :key_last4, null: false
      # Chosen by the nurse; never hardcoded in Ruby.
      t.string :model
      # Model ids from the provider's list-models response at the last successful check.
      t.jsonb :available_models, null: false, default: []
      t.datetime :validated_at
      t.string :last_error_code
      t.datetime :last_checked_at
      t.timestamps
    end
    add_index :provider_credentials, %i[user_id provider], unique: true
  end
end
