# Devise replaces Rails' generated authentication. Both store bcrypt hashes,
# so existing passwords keep working once the columns carry Devise's names.
class MoveUsersToDevise < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :email_address, :email
    rename_column :users, :password_digest, :encrypted_password
    add_column :users, :remember_created_at, :datetime

    # Devise keeps the sign-in in the encrypted session cookie, not a table.
    drop_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end
  end
end
