class CreateIngredientDescriptors < ActiveRecord::Migration[8.1]
  def change
    # Harmless modifier words ("diced", "fresh", "cups") the engine may ignore
    # when everything else in an ingredient phrase was recognized.
    create_table :ingredient_descriptors do |t|
      t.string :word, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :ingredient_descriptors, :word, unique: true
  end
end
