class CreateTenantsAndMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :tenants do |t|
      t.string :name, null: false
      t.string :plan, null: false, default: "basic"
      t.string :api_token_public_key
      t.string :features, array: true, null: false, default: []
      # The Basic tenant every user gets with their account.
      t.boolean :personal, null: false, default: false

      t.timestamps
    end

    add_index :tenants, :plan

    create_table :memberships do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"

      t.timestamps
    end

    add_index :memberships, [ :tenant_id, :user_id ], unique: true

    add_reference :users, :last_tenant, null: true, foreign_key: { to_table: :tenants, on_delete: :nullify }

    # Filled by BackfillPersonalTenants and made required by FinalizeTenantOwnership.
    add_reference :bundles, :tenant, null: true, foreign_key: true
    add_reference :contracts, :tenant, null: true, foreign_key: true
    add_reference :contract_validation_records, :tenant, null: true, foreign_key: true
  end
end
