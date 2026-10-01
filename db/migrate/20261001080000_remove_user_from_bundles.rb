# Bundles are sent by their tenant; the user who created one is no longer tracked.
class RemoveUserFromBundles < ActiveRecord::Migration[8.1]
  def change
    remove_reference :bundles, :user, foreign_key: true, index: true, null: true
  end
end
