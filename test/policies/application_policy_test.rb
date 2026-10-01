require "test_helper"

class ApplicationPolicyTest < ActiveSupport::TestCase
  test "base policy denies operations even for admins" do
    users(:one).update_column(:features, [ "admin" ])
    context = AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one))

    [ context, nil ].each do |principal|
      policy = ApplicationPolicy.new(principal, tenants(:one))
      [ :index?, :show?, :create?, :new?, :update?, :edit?, :destroy? ].each do |query|
        assert_not policy.public_send(query)
      end
    end
  end

  test "base scope requires an explicit implementation" do
    assert_raises(NotImplementedError) { ApplicationPolicy::Scope.new(nil, Tenant.all).resolve }
  end

  test "namespace lookup preserves policy subject and principal" do
    context = AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one))
    bundle_access = SigningBundleAccess.new(bundle: bundles(:one), recipient: nil)
    session_access = SigningSessionAccess.new(contract: nil, session: nil, signer_contract: nil, token_authorized: false)
    subjects = {
      [ :api, :v1, Bundle ] => Api::V1::BundlePolicy,
      [ :api, :v1, Contract ] => Api::V1::ContractPolicy,
      [ :api, :v1, Document ] => Api::V1::DocumentPolicy,
      [ :api, :v1, :hello ] => Api::V1::HelloPolicy,
      [ :api, :federation, :v1, Recipient.new ] => Api::Federation::V1::RecipientPolicy,
      [ :api, :federation, :v1, FederationRequestInvitation ] => Api::Federation::V1::FederationRequestInvitationPolicy,
      [ :received, Bundle ] => Received::BundlePolicy,
      [ :received, FederationRequestInvitation ] => Received::FederationRequestInvitationPolicy,
      [ :signing, bundle_access ] => Signing::SigningBundleAccessPolicy,
      [ :signing, session_access ] => Signing::SigningSessionAccessPolicy,
      [ :tenant_selection, tenants(:one) ] => TenantSelection::TenantPolicy,
      [ :tenant_selection, :tenant ] => TenantSelection::TenantPolicy
    }

    subjects.each do |subject, policy_class|
      policy = Pundit.policy!(context, subject)

      assert_instance_of policy_class, policy
      assert_same subject.last, policy.record
      assert_same context, policy.context
    end
  end

  test "namespace lookup resolves collection scopes" do
    subjects = {
      [ :api, :v1, Bundle ] => Api::V1::BundlePolicy::Scope,
      [ :api, :v1, Contract ] => Api::V1::ContractPolicy::Scope,
      [ :api, :v1, Document ] => Api::V1::DocumentPolicy::Scope,
      [ :api, :federation, :v1, FederationRequestInvitation ] => Api::Federation::V1::FederationRequestInvitationPolicy::Scope,
      [ :received, Bundle ] => Received::BundlePolicy::Scope,
      [ :received, FederationRequestInvitation ] => Received::FederationRequestInvitationPolicy::Scope
    }

    subjects.each do |subject, scope_class|
      assert_equal scope_class, Pundit::PolicyFinder.new(subject).scope
    end
  end

  test "admin gate requires a web user with the admin feature" do
    admin = users(:one)
    admin.update_column(:features, [ "admin" ])

    assert AdminPolicy.new(AuthorizationContext::Web.new(user: admin, tenant: nil), :admin).access?
    assert_not AdminPolicy.new(AuthorizationContext::Web.new(user: users(:two), tenant: tenants(:two)), :admin).access?
    assert_not AdminPolicy.new(AuthorizationContext::Web.new(user: nil, tenant: nil), :admin).access?
    assert_not AdminPolicy.new(nil, :admin).access?
  end
end
