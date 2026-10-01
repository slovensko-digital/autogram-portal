# Contracts and their validation records belong to a tenant; the user who created them is no longer tracked.
class RemoveUserFromContracts < ActiveRecord::Migration[8.1]
  def change
    remove_reference :contracts, :user, foreign_key: true, index: true, null: true
    remove_reference :contract_validation_records, :user, foreign_key: true, index: true, null: true
  end
end
