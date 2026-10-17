class CreateTaxonomyAliases < ActiveRecord::Migration[8.1]
  def change
    create_table :taxonomy_aliases do |t|
      t.references :taxonomy_node, null: false, foreign_key: { on_delete: :cascade }
      t.string :term, null: false
      t.timestamps
    end

    add_index :taxonomy_aliases, :term, unique: true
    add_index :taxonomy_aliases, :term, using: :gin, opclass: :gin_trgm_ops, name: "index_taxonomy_aliases_on_term_trgm"
  end
end
