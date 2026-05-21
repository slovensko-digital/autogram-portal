class AddAuthorNotificationsEnabledToBundlesAndContracts < ActiveRecord::Migration[8.1]
  def change
    add_column :bundles, :author_notifications_enabled, :boolean, default: false, null: false
    add_column :contracts, :author_notifications_enabled, :boolean, default: false, null: false
  end
end
