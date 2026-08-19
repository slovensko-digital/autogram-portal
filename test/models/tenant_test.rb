require "test_helper"

# == Schema Information
#
# Table name: tenants
#
#  id                   :bigint           not null, primary key
#  api_token_identifier :string           not null
#  api_token_public_key :text
#  features             :text             default([]), not null, is an Array
#  kind                 :string           default("freemium"), not null
#  name                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_tenants_on_api_token_identifier  (api_token_identifier) UNIQUE
#
class TenantTest < ActiveSupport::TestCase
  test "validates and exposes available features" do
    tenant = Tenant.new(name: "Enabled", features: %w[archivation api federation])

    assert tenant.valid?
    assert tenant.archivation_enabled?
    assert tenant.api_enabled?
    assert tenant.federation_enabled?
    assert tenant.feature_enabled?(:api)

    tenant.features = [ "unsupported" ]

    assert_not tenant.valid?
    assert_includes tenant.errors[:features].to_sentence, "unsupported"

    tenant.features = nil

    assert_not tenant.valid?
    assert_predicate tenant.errors[:features], :any?
  end

  test "generates a unique api_token_identifier on create" do
    tenant = Tenant.create!(name: "New tenant", kind: :organization)

    assert_predicate tenant.api_token_identifier, :present?
    assert_match(/\A[0-9a-f-]{36}\z/, tenant.api_token_identifier)
  end

  test "freemium personal tenant membership is admin" do
    tenant = tenants(:one)

    assert tenant.tenant_users.find_by(user: users(:one))&.admin?
  end

  test "freemium tenant accepts only one member" do
    tenant = tenants(:one)
    membership = tenant.tenant_users.build(user: users(:two))

    assert_not membership.valid?
    assert_includes membership.errors[:tenant], "freemium tenants can only have one member"
  end

  test "tenant cannot become freemium with multiple members" do
    tenant = Tenant.create!(name: "Organization", kind: :organization)
    tenant.tenant_users.create!(user: users(:one), role: :admin)
    tenant.tenant_users.create!(user: users(:two), role: :member)

    tenant.kind = :freemium

    assert_not tenant.valid?
    assert_includes tenant.errors[:tenant_users], "freemium tenants can only have one member"
  end

  test "organization tenant accepts multiple members" do
    tenant = Tenant.create!(name: "Organization", kind: :organization)

    assert tenant.tenant_users.create(user: users(:one), role: :admin).persisted?
    assert tenant.tenant_users.create(user: users(:two), role: :member).persisted?
    assert_equal 2, tenant.users.count
  end
end
