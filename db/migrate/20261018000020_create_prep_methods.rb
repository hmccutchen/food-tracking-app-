class CreatePrepMethods < ActiveRecord::Migration[8.1]
  def change
    create_table :prep_methods do |t|
      t.string :name, null: false
      # Whole words that detect the method in a dish name, prep note or ingredient.
      t.string :keywords, array: true, null: false, default: []
      t.text :risk, null: false
      t.text :lower_risk_method, null: false
      t.text :caveat, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :prep_methods, :name, unique: true

    create_table :prep_method_risks do |t|
      t.references :prep_method, null: false, foreign_key: { on_delete: :cascade }
      t.references :taxonomy_node, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :prep_method_risks, %i[prep_method_id taxonomy_node_id], unique: true
  end
end
