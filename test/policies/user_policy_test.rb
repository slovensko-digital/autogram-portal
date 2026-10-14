require "test_helper"

class UserPolicyTest < ActiveSupport::TestCase
  setup do
    @context = AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one))
  end

  test "account management is self-only even for admins" do
    users(:one).update_column(:features, [ "admin" ])

    assert UserPolicy.new(@context, users(:one)).manage_account?
    assert_not UserPolicy.new(@context, users(:two)).manage_account?
  end

  test "ordinary user manages own account" do
    assert UserPolicy.new(@context, users(:one)).manage_account?
  end

  test "missing and non-web principals cannot manage accounts" do
    assert_not UserPolicy.new(nil, users(:one)).manage_account?
    context = AuthorizationContext::TenantApi.new(tenant: tenants(:one))
    assert_not UserPolicy.new(context, users(:one)).manage_account?
  end
end
