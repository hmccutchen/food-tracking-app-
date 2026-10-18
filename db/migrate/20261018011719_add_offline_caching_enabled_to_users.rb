class AddOfflineCachingEnabledToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :offline_caching_enabled, :boolean, default: true, null: false
  end
end
