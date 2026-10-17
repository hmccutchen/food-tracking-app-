class CreateTaxonomyNodes < ActiveRecord::Migration[8.1]
  def change
    create_table :taxonomy_nodes do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :kind, null: false, default: "ingredient"
      t.references :parent, foreign_key: { to_table: :taxonomy_nodes, on_delete: :nullify }
      t.timestamps
    end

    add_index :taxonomy_nodes, :name, unique: true
    add_index :taxonomy_nodes, :slug, unique: true
    add_index :taxonomy_nodes, :kind
    add_index :taxonomy_nodes, :name, using: :gin, opclass: :gin_trgm_ops, name: "index_taxonomy_nodes_on_name_trgm"
  end
end
