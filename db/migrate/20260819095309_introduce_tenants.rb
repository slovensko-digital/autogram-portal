class IntroduceTenants < ActiveRecord::Migration[8.1]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
  end

  class MigrationTenant < ActiveRecord::Base
    self.table_name = "tenants"
  end

  class MigrationTenantUser < ActiveRecord::Base
    self.table_name = "tenant_users"
  end

  class MigrationBundle < ActiveRecord::Base
    self.table_name = "bundles"
  end

  class MigrationContract < ActiveRecord::Base
    self.table_name = "contracts"
  end

  class MigrationContractValidationRecord < ActiveRecord::Base
    self.table_name = "contract_validation_records"
  end

  def up
    create_tenant_tables
    add_tenant_columns
    reset_column_information
    backfill_tenants
    backfill_resource_tenants
    ensure_backfill_complete!
    replace_user_scoped_validation_index
    enforce_tenant_constraints
    remove_resource_user_columns
    remove_column :users, :features
    remove_column :users, :api_token_public_key
  end

  def down
    restore_user_columns
    reset_column_information
    restore_user_features_and_api_key
    restore_resource_users
    restore_user_scoped_validation_index
    enforce_legacy_user_constraints
    remove_tenant_columns
    drop_table :tenant_users
    drop_table :tenants
  end

  private

  def create_tenant_tables
    create_table :tenants do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: "freemium"
      t.text :features, array: true, null: false, default: []
      t.text :api_token_public_key
      t.string :api_token_identifier, null: false
      t.timestamps
      t.index :api_token_identifier, unique: true
    end

    create_table :tenant_users do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :role, null: false, default: "member"
      t.timestamps
      t.index [ :tenant_id, :user_id ], unique: true
    end
  end

  def add_tenant_columns
    add_column :users, :admin, :boolean, null: false, default: false
    add_reference :users, :current_tenant, null: true, foreign_key: { to_table: :tenants, on_delete: :nullify }
    add_reference :bundles, :tenant, null: true, foreign_key: { on_delete: :cascade }
    add_reference :contracts, :tenant, null: true, foreign_key: { on_delete: :cascade }
    add_reference :contract_validation_records, :tenant, null: true, foreign_key: { on_delete: :cascade }
  end

  def reset_column_information
    [
      MigrationUser,
      MigrationTenant,
      MigrationTenantUser,
      MigrationBundle,
      MigrationContract,
      MigrationContractValidationRecord
    ].each(&:reset_column_information)
  end

  def backfill_tenants
    MigrationUser.find_each do |user|
      features = Array(user.features)
      tenant = MigrationTenant.create!(
        name: user.name.presence || user.email.presence || "Personal tenant",
        kind: "freemium",
        features: features & %w[archivation api federation],
        api_token_public_key: user.api_token_public_key,
        api_token_identifier: user.id.to_s,
        created_at: user.created_at,
        updated_at: user.updated_at
      )
      MigrationTenantUser.create!(
        tenant_id: tenant.id,
        user_id: user.id,
        role: "admin",
        created_at: user.created_at,
        updated_at: user.updated_at
      )
      user.update_columns(current_tenant_id: tenant.id, admin: features.include?("admin"))
    end
  end

  def backfill_resource_tenants
    execute <<~SQL.squish
      UPDATE bundles
      SET tenant_id = users.current_tenant_id
      FROM users
      WHERE bundles.user_id = users.id
    SQL

    execute <<~SQL.squish
      UPDATE contracts
      SET tenant_id = bundles.tenant_id
      FROM bundles
      WHERE contracts.bundle_id = bundles.id
    SQL

    execute <<~SQL.squish
      UPDATE contracts
      SET tenant_id = users.current_tenant_id
      FROM users
      WHERE contracts.tenant_id IS NULL
        AND contracts.user_id = users.id
    SQL

    execute <<~SQL.squish
      UPDATE contract_validation_records
      SET tenant_id = contracts.tenant_id
      FROM contracts
      WHERE contract_validation_records.contract_id = contracts.id
        AND contracts.tenant_id IS NOT NULL
    SQL

    execute <<~SQL.squish
      UPDATE contract_validation_records
      SET tenant_id = users.current_tenant_id
      FROM users
      WHERE contract_validation_records.tenant_id IS NULL
        AND contract_validation_records.user_id = users.id
    SQL
  end

  def ensure_backfill_complete!
    incomplete = {
      users: "SELECT COUNT(*) FROM users WHERE current_tenant_id IS NULL",
      tenants: "SELECT COUNT(*) FROM tenants WHERE api_token_identifier IS NULL OR api_token_identifier = ''",
      bundles: "SELECT COUNT(*) FROM bundles WHERE tenant_id IS NULL",
      contracts: <<~SQL.squish,
        SELECT COUNT(*)
        FROM contracts
        WHERE tenant_id IS NULL
          AND (user_id IS NOT NULL OR bundle_id IS NOT NULL)
      SQL
      contract_validation_records: "SELECT COUNT(*) FROM contract_validation_records WHERE tenant_id IS NULL"
    }.filter_map do |resource, query|
      count = select_value(query).to_i
      "#{count} #{resource}" if count.positive?
    end

    return if incomplete.empty?

    raise ActiveRecord::MigrationError, "Tenant backfill incomplete: #{incomplete.join(', ')}"
  end

  def replace_user_scoped_validation_index
    remove_index :contract_validation_records, name: "index_contract_validation_records_on_user_contract_and_version"
    add_index :contract_validation_records,
              [ :tenant_id, :source_contract_uuid, :source_version_number ],
              unique: true,
              name: "index_contract_validation_records_on_tenant_contract_version"
  end

  def enforce_tenant_constraints
    change_column_null :bundles, :tenant_id, false
    change_column_null :contract_validation_records, :tenant_id, false
  end

  def remove_resource_user_columns
    remove_reference :bundles, :user, foreign_key: true
    remove_reference :contracts, :user, foreign_key: true
    remove_reference :contract_validation_records, :user, foreign_key: true
  end

  def restore_user_columns
    add_column :users, :features, :text, array: true, default: []
    add_column :users, :api_token_public_key, :string
    add_reference :bundles, :user, null: true, foreign_key: true
    add_reference :contracts, :user, null: true, foreign_key: true
    add_reference :contract_validation_records, :user, null: true, foreign_key: true
  end

  def restore_user_features_and_api_key
    MigrationUser.find_each do |user|
      personal_tenant = MigrationTenant
        .joins("INNER JOIN tenant_users ON tenant_users.tenant_id = tenants.id")
        .where(kind: "freemium", tenant_users: { user_id: user.id, role: "admin" })
        .order(:id)
        .first
      features = Array(personal_tenant&.features)
      features << "admin" if user.admin?

      user.update_columns(
        features: features.uniq,
        api_token_public_key: personal_tenant&.api_token_public_key
      )
    end
  end

  def restore_resource_users
    %i[bundles contracts contract_validation_records].each do |table|
      execute <<~SQL.squish
        UPDATE #{table}
        SET user_id = (
          SELECT tenant_users.user_id
          FROM tenant_users
          WHERE tenant_users.tenant_id = #{table}.tenant_id
          ORDER BY CASE tenant_users.role WHEN 'admin' THEN 0 ELSE 1 END, tenant_users.id
          LIMIT 1
        )
        WHERE tenant_id IS NOT NULL
      SQL
    end

    unrestorable = {
      bundles: select_value("SELECT COUNT(*) FROM bundles WHERE user_id IS NULL").to_i,
      contract_validation_records: select_value("SELECT COUNT(*) FROM contract_validation_records WHERE user_id IS NULL").to_i
    }.select { |_resource, count| count.positive? }

    return if unrestorable.empty?

    details = unrestorable.map { |resource, count| "#{count} #{resource}" }.join(", ")
    raise ActiveRecord::IrreversibleMigration, "Cannot restore required user ownership for #{details}"
  end

  def restore_user_scoped_validation_index
    remove_index :contract_validation_records, name: "index_contract_validation_records_on_tenant_contract_version"
    add_index :contract_validation_records,
              [ :user_id, :source_contract_uuid, :source_version_number ],
              unique: true,
              name: "index_contract_validation_records_on_user_contract_and_version"
  end

  def enforce_legacy_user_constraints
    change_column_null :bundles, :user_id, false
    change_column_null :contract_validation_records, :user_id, false
  end

  def remove_tenant_columns
    remove_reference :contract_validation_records, :tenant, foreign_key: true
    remove_reference :contracts, :tenant, foreign_key: true
    remove_reference :bundles, :tenant, foreign_key: true
    remove_reference :users, :current_tenant, foreign_key: { to_table: :tenants }
    remove_column :users, :admin
  end
end
