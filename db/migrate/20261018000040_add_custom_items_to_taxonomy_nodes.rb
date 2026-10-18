# Custom items: taxonomy nodes the nurse adds herself when a food or ingredient
# isn't in USDA or the seeded taxonomy. The seed loader never touches them.
class AddCustomItemsToTaxonomyNodes < ActiveRecord::Migration[8.1]
  def change
    change_table :taxonomy_nodes, bulk: true do |t|
      t.string :source, null: false, default: "seed"
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :ingredients_text
      t.index :source
    end
  end
end
