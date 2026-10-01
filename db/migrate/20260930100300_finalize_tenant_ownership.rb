# Records belong to tenants now: the backfilled tenant columns become required
# and the user columns they replace are dropped.
class FinalizeTenantOwnership < ActiveRecord::Migration[8.1]
  OWNED_TABLES = %i[bundles contracts contract_validation_records].freeze

  def up
    change_column_null :bundles, :tenant_id, false
    change_column_null :contract_validation_records, :tenant_id, false

    remove_index :contract_validation_records, name: "index_contract_validation_records_on_user_contract_and_version"
    remove_index :contract_validation_records, name: "index_contract_validation_records_on_user_id_and_expires_at"
    add_index :contract_validation_records, [ :tenant_id, :source_contract_uuid, :source_version_number ],
      unique: true, name: "index_cvr_on_tenant_contract_and_version"
    add_index :contract_validation_records, [ :tenant_id, :expires_at ]

    OWNED_TABLES.each { |table| remove_reference table, :user, foreign_key: true, index: true }
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

    # Records go back to the first owner of their tenant.
    OWNED_TABLES.each do |table|
      add_reference table, :user, foreign_key: true, index: true
      execute <<~SQL
        UPDATE #{table}
        SET user_id = (
          SELECT memberships.user_id FROM memberships
          WHERE memberships.tenant_id = #{table}.tenant_id AND memberships.role = 'owner'
          ORDER BY memberships.id
          LIMIT 1
        )
      SQL
    end
    change_column_null :bundles, :user_id, false
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
