require "test_helper"

class TenantPolicyTest < ActiveSupport::TestCase
  setup do
    @tenant = tenants(:one)
    @owner = users(:one)
  end

  test "owner can update and manage memberships without api access" do
    policy = tenant_policy(@owner)

    assert policy.update?
    assert policy.manage_memberships?
    assert_not policy.edit_api_key?
    assert_empty policy.permitted_attributes_for_update
  end

  test "api access permits only the api public key" do
    @tenant.update!(features: [ "api" ])
    policy = tenant_policy(@owner)

    assert policy.edit_api_key?
    assert_equal [ :api_token_public_key ], policy.permitted_attributes_for_update
  end

  test "member can leave but cannot manage the organization" do
    @tenant.update!(plan: :pro)
    @tenant.memberships.create!(user: users(:two))
    policy = tenant_policy(users(:two))

    assert policy.leave?
    assert_not policy.update?
    assert_not policy.manage_memberships?
    assert_not policy.edit_api_key?
  end

  test "last owner may attempt leaving so the model supplies the error" do
    assert tenant_policy(@owner).leave?
  end

  test "ownership in another selected tenant does not grant management" do
    policy = tenant_policy(@owner, selected_tenant: tenants(:two))

    assert_not policy.update?
    assert_not policy.manage_memberships?
    assert_not policy.leave?
  end

  test "anonymous and missing tenant contexts grant no access" do
    [ tenant_policy(nil), tenant_policy(@owner, selected_tenant: nil) ].each do |policy|
      assert_not policy.update?
      assert_not policy.manage_memberships?
      assert_not policy.leave?
    end
  end

  test "admin is not an organization owner by default" do
    users(:two).update_column(:features, [ "admin" ])
    policy = tenant_policy(users(:two))

    assert_not policy.update?
    assert_not policy.manage_memberships?
    assert_not policy.leave?
  end

  private

  def tenant_policy(user, selected_tenant: @tenant)
    TenantPolicy.new(AuthorizationContext::Web.new(user: user, tenant: selected_tenant), @tenant)
  end
end
