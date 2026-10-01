require "test_helper"

class FederationPolicyTest < ActiveSupport::TestCase
  setup do
    @portal = PortalInstance.new(id: 123)
    @context = AuthorizationContext::Portal.new(portal_instance: @portal)
    @recipient = Recipient.new(portal_instance: @portal, federation_mode: "federated")
  end

  test "assigned portal can read and claim independently of workflow state" do
    policy = Api::Federation::V1::RecipientPolicy.new(@context, @recipient)

    assert policy.show?
    assert policy.claim?
    @recipient.withdrawn_at = Time.current
    assert policy.claim?
  end

  test "different portal and non-federated recipient are denied" do
    @recipient.portal_instance = PortalInstance.new(id: 456)
    assert_not Api::Federation::V1::RecipientPolicy.new(@context, @recipient).show?

    @recipient.portal_instance = nil
    @recipient.federation_mode = "local"
    assert_not Api::Federation::V1::RecipientPolicy.new(@context, @recipient).claim?
  end

  test "portal invitation creation and withdrawal use caller ownership" do
    invitation = FederationRequestInvitation.new(portal_instance: @portal)
    policy = Api::Federation::V1::FederationRequestInvitationPolicy.new(@context, invitation)

    assert policy.create?
    assert policy.withdraw?
    invitation.portal_instance = PortalInstance.new(id: 456)
    assert_not policy.withdraw?
  end

  test "web and tenant API cannot impersonate portal principal" do
    contexts = [
      nil,
      AuthorizationContext::Portal.new(portal_instance: nil),
      AuthorizationContext::TenantApi.new(tenant: tenants(:one)),
      AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one))
    ]

    contexts.each do |context|
      assert_not Api::Federation::V1::RecipientPolicy.new(context, @recipient).claim?
      assert_not Api::Federation::V1::FederationRequestInvitationPolicy.new(context, FederationRequestInvitation).create?
      assert_empty Api::Federation::V1::FederationRequestInvitationPolicy::Scope.new(context, FederationRequestInvitation.all).resolve
    end
  end

  test "broker claim requires a signed-in user" do
    anonymous = AuthorizationContext::Web.new(user: nil, tenant: nil)
    policy = FederationRequestPolicy.new(anonymous, :federation_request)

    assert_not policy.claim?
    context = AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one))
    assert FederationRequestPolicy.new(context, :federation_request).claim?
  end
end
