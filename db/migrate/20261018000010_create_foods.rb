class CreateFoods < ActiveRecord::Migration[8.1]
  def change
    create_table :foods do |t|
      t.bigint :fdc_id, null: false
      t.string :source, null: false
      t.string :data_type, null: false
      t.string :description, null: false
      t.string :category
      # Raw ingredient text, kept verbatim. Foundation and SR Legacy have none (nil);
      # Branded foods will fill it from branded_food.csv.
      t.text :ingredients_text
      t.date :publication_date
      t.datetime :imported_at, null: false
      # The original food.csv row, verbatim.
      t.jsonb :raw, null: false, default: {}
      t.references :taxonomy_node, foreign_key: { on_delete: :nullify }
      t.string :match_type, null: false, default: "unresolved"
      t.string :match_reason
      t.timestamps
    end

    add_index :foods, :fdc_id, unique: true
    add_index :foods, :source
    add_index :foods, :description, using: :gin, opclass: :gin_trgm_ops
  end
end
