require "test_helper"

class SessionPolicyTest < ActiveSupport::TestCase
  setup do
    @contract = Contract.new(tenant: tenants(:one))
    @signer_contract = SignerContract.new(contract: @contract, signer: UserSigner.new(user: users(:one)))
    @session = AutogramSession.new(signer_contract: @signer_contract)
    @access = SigningSessionAccess.new(contract: @contract, session: @session, signer_contract: @signer_contract, token_authorized: false)
    @anonymous = AuthorizationContext::Web.new(user: nil, tenant: nil)
  end

  test "creation requires a contract and its bound signer contract" do
    assert Signing::SigningSessionAccessPolicy.new(@anonymous, @access).create?
    assert_not Signing::SigningSessionAccessPolicy.new(@anonymous, @access.with(signer_contract: nil)).create?
    assert_not Signing::SigningSessionAccessPolicy.new(@anonymous, @access.with(contract: nil, signer_contract: nil)).create?
  end

  test "verified bound token permits content operations but never deletion" do
    policy = Signing::SigningSessionAccessPolicy.new(@anonymous, @access.with(token_authorized: true))

    assert policy.parameters?
    assert policy.download?
    assert policy.upload?
    assert policy.state?
    assert_not policy.destroy?
  end

  test "user signer can access and delete their session outside the selected tenant" do
    context = AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:two))
    policy = Signing::SigningSessionAccessPolicy.new(context, @access)

    assert policy.parameters?
    assert policy.destroy?
  end

  test "selected tenant manager can access sessions of other signers" do
    @signer_contract.signer = UserSigner.new(user: users(:two))
    context = AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one))

    assert Signing::SigningSessionAccessPolicy.new(context, @access).upload?
    assert Signing::SigningSessionAccessPolicy.new(context, @access).destroy?
  end

  test "unrelated admin is not an allowed user" do
    users(:two).update_column(:features, [ "admin" ])
    context = AuthorizationContext::Web.new(user: users(:two), tenant: tenants(:two))
    policy = Signing::SigningSessionAccessPolicy.new(context, @access)

    assert_not policy.parameters?
    assert_not policy.state?
    assert_not policy.destroy?
  end

  test "withdrawn recipient loses user access while manager access is preserved" do
    recipient = Recipient.new(user: users(:one), email: users(:one).email)
    @signer_contract.signer = RecipientSigner.new(recipient: recipient)
    context = AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:two))
    policy = Signing::SigningSessionAccessPolicy.new(context, @access)
    assert policy.upload?

    recipient.withdrawn_at = Time.current
    assert_not policy.upload?
    assert_not policy.destroy?

    manager_context = AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one))
    assert Signing::SigningSessionAccessPolicy.new(manager_context, @access).destroy?
  end

  test "verification mutations require resolved signer and session to match" do
    policy = Signing::SigningSessionAccessPolicy.new(@anonymous, @access.with(signer_contract: SignerContract.new))

    assert policy.show?
    assert_not policy.request_verification?
    assert_not policy.verify_verification?
    assert_not policy.complete_signing?
  end

  test "session must belong to the bound contract even with a token fact" do
    access = @access.with(contract: Contract.new(tenant: tenants(:two)), token_authorized: true)
    policy = Signing::SigningSessionAccessPolicy.new(@anonymous, access)

    assert_not policy.show?
    assert_not policy.upload?
    assert_not policy.destroy?
  end

  test "missing and non-web principals cannot use session operations" do
    contexts = [
      nil,
      AuthorizationContext::TenantApi.new(tenant: tenants(:one)),
      AuthorizationContext::Portal.new(portal_instance: nil)
    ]

    contexts.each do |context|
      policy = Signing::SigningSessionAccessPolicy.new(context, @access.with(token_authorized: true))

      assert_not policy.create?
      assert_not policy.show?
      assert_not policy.upload?
      assert_not policy.destroy?
    end
  end
end
