class CreatePatients < ActiveRecord::Migration[8.1]
  def change
    create_table :patients do |t|
      t.references :user, null: false, foreign_key: true
      # Encrypted with Active Record Encryption (non-deterministic).
      t.string :display_name, null: false
      t.text :notes
      t.integer :profile_version, null: false, default: 1
      t.timestamps
    end
  end
end
