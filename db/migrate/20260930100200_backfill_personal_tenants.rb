# Every existing user gets a personal tenant that owns all of their data.
#
# The tenant reuses the user's id, so existing API clients that sign JWTs with
# `sub = user.id` keep working now that `sub` identifies a tenant.
class BackfillPersonalTenants < ActiveRecord::Migration[8.1]
  TENANT_FEATURES = %w[archivation api].freeze

  def up
    execute <<~SQL
      INSERT INTO tenants (id, name, plan, personal, api_token_public_key, features, created_at, updated_at)
      SELECT
        users.id,
        COALESCE(NULLIF(users.name, ''), users.email, 'Tenant ' || users.id),
        CASE WHEN 'api' = ANY(users.features) THEN 'pro' ELSE 'basic' END,
        TRUE,
        users.api_token_public_key,
        ARRAY(SELECT unnest(users.features) INTERSECT SELECT unnest(ARRAY[#{quoted_features}]::text[]) ORDER BY 1)::varchar[],
        NOW(),
        NOW()
      FROM users
    SQL

    execute <<~SQL
      SELECT setval('tenants_id_seq', GREATEST((SELECT COALESCE(MAX(id), 0) FROM tenants), 1), (SELECT COUNT(*) > 0 FROM tenants))
    SQL

    execute <<~SQL
      INSERT INTO memberships (tenant_id, user_id, role, created_at, updated_at)
      SELECT users.id, users.id, 'owner', NOW(), NOW() FROM users
    SQL

    execute "UPDATE users SET last_tenant_id = id"

    execute "UPDATE bundles SET tenant_id = user_id"
    # Bundled contracts always belong to the tenant of their bundle.
    execute <<~SQL
      UPDATE contracts
      SET tenant_id = bundles.tenant_id
      FROM bundles
      WHERE bundles.id = contracts.bundle_id
    SQL
    execute "UPDATE contracts SET tenant_id = user_id WHERE bundle_id IS NULL AND user_id IS NOT NULL"
    execute "UPDATE contract_validation_records SET tenant_id = user_id"

    execute <<~SQL
      UPDATE users
      SET features = ARRAY(SELECT unnest(features) EXCEPT SELECT unnest(ARRAY[#{quoted_features}]::text[]) ORDER BY 1)
    SQL
  end

  def down
    execute <<~SQL
      UPDATE users
      SET features = ARRAY(SELECT DISTINCT unnest(users.features || tenants.features::text[]) ORDER BY 1)
      FROM tenants
      WHERE tenants.id = users.id
    SQL

    execute "UPDATE contract_validation_records SET tenant_id = NULL"
    execute "UPDATE contracts SET tenant_id = NULL"
    execute "UPDATE bundles SET tenant_id = NULL"
    execute "UPDATE users SET last_tenant_id = NULL"
    execute "DELETE FROM memberships"
    execute "DELETE FROM tenants"
  end

  private

  def quoted_features
    TENANT_FEATURES.map { |feature| connection.quote(feature) }.join(", ")
  end
end
