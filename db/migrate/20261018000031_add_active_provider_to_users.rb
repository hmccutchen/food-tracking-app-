class AddActiveProviderToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :active_provider, :string
  end
end
