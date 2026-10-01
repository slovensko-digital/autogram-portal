class FinalizeTenantOwnership < ActiveRecord::Migration[8.1]
  def up
    change_column_null :bundles, :tenant_id, false
    change_column_null :contract_validation_records, :tenant_id, false

    remove_index :contract_validation_records, name: "index_contract_validation_records_on_user_contract_and_version"
    remove_index :contract_validation_records, name: "index_contract_validation_records_on_user_id_and_expires_at"
    add_index :contract_validation_records, [ :tenant_id, :source_contract_uuid, :source_version_number ],
      unique: true, name: "index_cvr_on_tenant_contract_and_version"
    add_index :contract_validation_records, [ :tenant_id, :expires_at ]
    change_column_null :contract_validation_records, :user_id, true

    remove_column :users, :api_token_public_key
  end

  def down
    add_column :users, :api_token_public_key, :string
    execute <<~SQL
      UPDATE users
      SET api_token_public_key = tenants.api_token_public_key
      FROM tenants
      WHERE tenants.id = users.id
    SQL

    change_column_null :contract_validation_records, :user_id, false
    remove_index :contract_validation_records, [ :tenant_id, :expires_at ]
    remove_index :contract_validation_records, name: "index_cvr_on_tenant_contract_and_version"
    add_index :contract_validation_records, [ :user_id, :expires_at ], name: "index_contract_validation_records_on_user_id_and_expires_at"
    add_index :contract_validation_records, [ :user_id, :source_contract_uuid, :source_version_number ],
      unique: true, name: "index_contract_validation_records_on_user_contract_and_version"

    change_column_null :contract_validation_records, :tenant_id, true
    change_column_null :bundles, :tenant_id, true
  end
end
