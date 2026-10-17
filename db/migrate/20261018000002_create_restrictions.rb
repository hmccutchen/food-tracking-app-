class CreateRestrictions < ActiveRecord::Migration[8.1]
  def change
    create_table :restrictions do |t|
      t.references :patient, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      # term and note are encrypted with Active Record Encryption (non-deterministic).
      t.string :term, null: false
      t.text :note
      # Trade-off: taxonomy_node_id stays plaintext so the engine and avoid list
      # can join restrictions to the taxonomy. Someone with database access can
      # see which taxonomy node a restriction maps to (e.g. "peanut"), but not
      # the nurse's own wording or note, and not the patient's name.
      t.references :taxonomy_node, foreign_key: { on_delete: :nullify }
      t.string :match_type, null: false, default: "unresolved"
      t.string :match_reason
      t.timestamps
    end

    add_index :restrictions, :kind
  end
end
