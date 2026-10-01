require "test_helper"

class TenantSelectionPolicyTest < ActiveSupport::TestCase
  test "pending user can view and choose only their own tenant" do
    context = AuthorizationContext::PendingTenantSelection.new(user: users(:one))

    assert TenantSelection::TenantPolicy.new(context, :tenant).show?
    assert TenantSelection::TenantPolicy.new(context, tenants(:one)).update?
    assert_not TenantSelection::TenantPolicy.new(context, tenants(:two)).update?
  end

  test "pending user can create a tenant only when they have none" do
    user = users(:one)
    context = AuthorizationContext::PendingTenantSelection.new(user: user)
    policy = TenantSelection::TenantPolicy.new(context, :tenant)

    assert_not policy.create?
    Membership.where(user: user).delete_all
    assert policy.create?
  end

  test "signed in and anonymous contexts cannot act as pending users" do
    contexts = [
      nil,
      AuthorizationContext::PendingTenantSelection.new(user: nil),
      AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one))
    ]

    contexts.each do |context|
      policy = TenantSelection::TenantPolicy.new(context, tenants(:one))
      assert_not policy.show?
      assert_not policy.update?
      assert_not policy.create?
    end
  end

  test "pending context does not grant normal tenant or admin permissions" do
    users(:one).update_column(:features, [ "admin" ])
    context = AuthorizationContext::PendingTenantSelection.new(user: users(:one))

    assert_not TenantPolicy.new(context, tenants(:one)).update?
    assert_not TenantPolicy.new(context, tenants(:one)).leave?
    assert_not AdminPolicy.new(context, :admin).access?
  end
end
