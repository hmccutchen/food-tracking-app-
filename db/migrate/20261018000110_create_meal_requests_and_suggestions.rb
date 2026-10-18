class CreateMealRequestsAndSuggestions < ActiveRecord::Migration[8.1]
  def change
    create_table :meal_requests do |t|
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.integer :patient_ids, array: true, null: false, default: []
      # Encrypted: the nurse's own words may mention a patient or a condition.
      t.text :request_text
      t.string :status, null: false, default: "queued"
      # The provider that answered (for "Suggested preparation (from …)").
      t.string :provider
      # Plain, nurse-facing words only; never a raw exception. error_code is
      # an Ai::Error code (or "no_provider" / "no_patients" / "unexpected").
      t.string :error_message
      t.string :error_code
      t.integer :attempts_count, null: false, default: 0
      # Encrypted JSON array of conflict reasons (restriction terms are health data).
      t.text :blocking_conflicts
      t.jsonb :profile_versions, null: false, default: {}
      t.timestamps
    end
    add_index :meal_requests, %i[user_id created_at]

    create_table :meal_suggestions do |t|
      t.references :meal_request, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.string :dish, null: false
      t.jsonb :ingredients, null: false, default: []
      t.jsonb :prep_notes, null: false, default: []
      t.boolean :kept, null: false
      t.string :tier, null: false
      # Encrypted: the serialized Evaluation::GroupResult (flag reasons name restriction terms).
      t.text :result_json, null: false
      t.jsonb :profile_versions, null: false, default: {}
      t.datetime :evaluated_at, null: false
      t.timestamps
    end
    add_index :meal_suggestions, %i[meal_request_id position], unique: true
  end
end
