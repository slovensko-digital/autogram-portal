class AddTenantToOwnedRecords < ActiveRecord::Migration[8.1]
  def change
    add_reference :bundles, :tenant, null: true, foreign_key: true
    add_reference :contracts, :tenant, null: true, foreign_key: true
    add_reference :contract_validation_records, :tenant, null: true, foreign_key: true

    change_column_null :bundles, :user_id, true
  end
end
