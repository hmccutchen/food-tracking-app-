# Cross-cutting group membership. A node has one tree parent, but a nutrient
# group like "sodium" also covers nodes that live elsewhere in the tree
# (soy sauce stays under soy and is also a member of sodium).
class CreateTaxonomyMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :taxonomy_memberships do |t|
      t.references :node, null: false, foreign_key: { to_table: :taxonomy_nodes, on_delete: :cascade }
      t.references :group, null: false, index: false, foreign_key: { to_table: :taxonomy_nodes, on_delete: :cascade }
      t.timestamps
    end

    add_index :taxonomy_memberships, [ :group_id, :node_id ], unique: true
  end
end
