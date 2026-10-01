require "test_helper"

class BundlePolicyTest < ActiveSupport::TestCase
  setup do
    @context = AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one))
  end

  test "selected tenant members can manage bundles without an owner role" do
    tenants(:one).update!(plan: :pro)
    tenants(:one).memberships.create!(user: users(:two))
    context = AuthorizationContext::Web.new(user: users(:two), tenant: tenants(:one))
    policy = BundlePolicy.new(context, bundles(:one))

    [ :show?, :edit?, :update?, :destroy?, :manage_recipients? ].each do |query|
      assert policy.public_send(query)
    end
  end

  test "membership in another tenant does not permit its management" do
    tenants(:two).update!(plan: :pro)
    tenants(:two).memberships.create!(user: users(:one))
    policy = BundlePolicy.new(@context, bundles(:two))

    assert_not policy.show?
    assert_not policy.update?
    assert_not policy.destroy?
    assert_not policy.manage_recipients?
  end

  test "admin and public visibility do not bypass management ownership" do
    users(:one).update_column(:features, [ "admin" ])
    bundles(:two).update_column(:publicly_visible, true)

    assert_not BundlePolicy.new(@context, bundles(:two)).show?
  end

  test "scope includes only the selected tenant and preserves input constraints" do
    assert_equal [ bundles(:one) ], BundlePolicy::Scope.new(@context, Bundle.all).resolve.to_a
    assert_empty BundlePolicy::Scope.new(@context, Bundle.where(id: bundles(:two).id)).resolve
  end

  test "received scope follows the person rather than selected tenant ownership" do
    bundles(:two).recipients.create!(user: users(:one), email: "received@example.com")

    assert_includes Received::BundlePolicy::Scope.new(@context, Bundle.all).resolve, bundles(:two)
    assert_empty BundlePolicy::Scope.new(@context, Bundle.where(id: bundles(:two).id)).resolve
    assert_empty Received::BundlePolicy::Scope.new(nil, Bundle.all).resolve
    assert_empty Received::FederationRequestInvitationPolicy::Scope.new(nil, FederationRequestInvitation.all).resolve
  end

  test "missing principals and users without a selected tenant neither manage nor list tenant bundles" do
    contexts = [
      nil,
      AuthorizationContext::Web.new(user: nil, tenant: tenants(:one)),
      AuthorizationContext::Web.new(user: users(:one), tenant: nil)
    ]

    contexts.each do |context|
      policy = BundlePolicy.new(context, bundles(:one))
      assert_not policy.index?
      assert_not policy.show?
      assert_not policy.manage_recipients?
      assert_empty BundlePolicy::Scope.new(context, Bundle.all).resolve
    end
  end

  test "signing recipient capability is parent bound and independent of management" do
    recipient = Recipient.new(bundle: bundles(:two))
    access = SigningBundleAccess.new(bundle: bundles(:two), recipient: recipient)
    policy = Signing::SigningBundleAccessPolicy.new(@context, access)

    assert policy.sign?
    assert policy.autogram_batch?
    assert policy.accept?
    assert policy.decline?
    assert_not BundlePolicy.new(@context, bundles(:two)).manage?

    recipient.bundle = bundles(:one)
    assert_not policy.sign?
    assert_not policy.accept?
    assert_not policy.decline?
  end

  test "public bundle signing does not permit recipient accept or decline" do
    bundles(:two).update_column(:publicly_visible, true)
    context = AuthorizationContext::Web.new(user: nil, tenant: nil)
    access = SigningBundleAccess.new(bundle: bundles(:two), recipient: nil)
    policy = Signing::SigningBundleAccessPolicy.new(context, access)

    assert policy.sign?
    assert_not policy.accept?
    assert_not policy.decline?
    assert_not Signing::SigningBundleAccessPolicy.new(nil, access).sign?
    recipient = Recipient.new(bundle: bundles(:one))
    assert_not Signing::SigningBundleAccessPolicy.new(context, access.with(recipient: recipient)).sign?
  end
end
