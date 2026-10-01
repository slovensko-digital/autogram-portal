require "test_helper"

class UserPolicyTest < ActiveSupport::TestCase
  setup do
    @context = AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one))
  end

  test "account management is self-only even for admins" do
    users(:one).update_column(:features, [ "admin" ])

    assert UserPolicy.new(@context, users(:one)).manage_account?
    assert_not UserPolicy.new(@context, users(:two)).manage_account?
    assert_not UserPolicy.new(@context, users(:two)).edit_features?
  end

  test "ordinary user manages account but cannot edit feature flags" do
    policy = UserPolicy.new(@context, users(:one))

    assert policy.manage_account?
    assert_not policy.edit_features?
  end

  test "admin can edit own feature flags" do
    users(:one).update_column(:features, [ "admin" ])

    assert UserPolicy.new(@context, users(:one)).edit_features?
  end

  test "missing and non-web principals cannot manage accounts" do
    assert_not UserPolicy.new(nil, users(:one)).manage_account?
    context = AuthorizationContext::TenantApi.new(tenant: tenants(:one))
    assert_not UserPolicy.new(context, users(:one)).edit_features?
  end
end
