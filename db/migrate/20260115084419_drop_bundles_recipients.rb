class DropBundlesRecipients < ActiveRecord::Migration[8.1]
  def change
    drop_table :bundles_recipients, if_exists: true
  end
end
