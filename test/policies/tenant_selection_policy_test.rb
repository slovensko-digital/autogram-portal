require "test_helper"

class TenantSelectionPolicyTest < ActiveSupport::TestCase
  test "user without a selected tenant can view and choose only their own tenant" do
    context = AuthorizationContext::Web.new(user: users(:one), tenant: nil)

    assert TenantSelection::TenantPolicy.new(context, :tenant).show?
    assert TenantSelection::TenantPolicy.new(context, tenants(:one)).update?
    assert_not TenantSelection::TenantPolicy.new(context, tenants(:two)).update?
  end

  test "selected tenant, anonymous and non-web contexts cannot choose a tenant" do
    contexts = [
      nil,
      AuthorizationContext::Web.new(user: nil, tenant: nil),
      AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one)),
      AuthorizationContext::TenantApi.new(tenant: tenants(:one))
    ]

    contexts.each do |context|
      policy = TenantSelection::TenantPolicy.new(context, tenants(:one))
      assert_not policy.show?
      assert_not policy.update?
    end
  end

  test "a user without a selected tenant has no tenant permissions" do
    context = AuthorizationContext::Web.new(user: users(:one), tenant: nil)

    assert_not TenantPolicy.new(context, tenants(:one)).update?
    assert_not TenantPolicy.new(context, tenants(:one)).leave?
    assert_not BundlePolicy.new(context, bundles(:one)).show?
  end
end
