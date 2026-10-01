require "test_helper"

class ContractPolicyTest < ActiveSupport::TestCase
  setup do
    @context = AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one))
  end

  test "anonymous contract management is distinct from account-only actions" do
    policy = ContractPolicy.new(AuthorizationContext::Web.new(user: nil, tenant: nil), Contract.new)

    assert policy.show?
    assert policy.update?
    assert policy.destroy?
    assert_not policy.request_signatures?
    assert_not policy.signature_extension?
    assert_not policy.extend_signatures?
    assert_not policy.content_versions?
    assert_not policy.prepare_signature_fields?
  end

  test "anonymous contracts do not bypass the web principal boundary" do
    contexts = [
      nil,
      AuthorizationContext::TenantApi.new(tenant: tenants(:one)),
      AuthorizationContext::PendingTenantSelection.new(user: users(:one)),
      AuthorizationContext::Portal.new(portal_instance: nil)
    ]

    contexts.each do |context|
      policy = ContractPolicy.new(context, Contract.new)

      assert_not policy.show?
      assert_not policy.update?
      assert_not policy.destroy?
    end
  end

  test "intentional UUID-public access requires web context rather than API or pending principal" do
    contract = Contract.new(tenant: tenants(:two))
    anonymous = AuthorizationContext::Web.new(user: nil, tenant: nil)

    assert ContractPolicy.new(anonymous, contract).public_access?
    assert DocumentPolicy.new(anonymous, Document.new).download?
    assert SignatureEvidenceRecordPolicy.new(anonymous, SignatureEvidenceRecord).public_access?
    assert_not ContractPolicy.new(anonymous, contract).show?

    context = AuthorizationContext::TenantApi.new(tenant: tenants(:one))
    assert_not ContractPolicy.new(context, contract).public_access?
    assert_not DocumentPolicy.new(context, Document.new).download?
    assert_not SignatureEvidenceRecordPolicy.new(context, SignatureEvidenceRecord).public_access?
  end

  test "current tenant members can manage standalone and bundled contracts" do
    tenants(:one).update!(plan: :pro)
    tenants(:one).memberships.create!(user: users(:two))
    context = AuthorizationContext::Web.new(user: users(:two), tenant: tenants(:one))

    [ Contract.new(tenant: tenants(:one)), Contract.new(bundle: bundles(:one)) ].each do |contract|
      policy = ContractPolicy.new(context, contract)
      assert policy.show?
      assert policy.update?
      assert policy.destroy?
      assert policy.request_signatures?
      assert policy.extend_signatures?
    end
  end

  test "web ownership prioritizes direct tenant while field preparation uses bundle ownership" do
    contract = Contract.new(tenant: tenants(:two), bundle: bundles(:one))
    policy = ContractPolicy.new(@context, contract)

    assert_not policy.show?
    assert_not policy.update?
    assert_not policy.request_signatures?
    assert policy.prepare_signature_fields?
  end

  test "archive history requires management and the tenant archivation feature" do
    contract = Contract.new(tenant: tenants(:one))
    policy = ContractPolicy.new(@context, contract)
    assert_not policy.content_versions?

    tenants(:one).update_column(:features, [ "archivation" ])
    assert policy.content_versions?

    assert_not ContractPolicy.new(@context, Contract.new(tenant: tenants(:two))).content_versions?
  end

  test "admin does not bypass selected tenant ownership" do
    users(:one).update_column(:features, [ "admin" ])
    policy = ContractPolicy.new(@context, Contract.new(tenant: tenants(:two)))

    assert_not policy.show?
    assert_not policy.request_signatures?
    assert_not policy.signature_extension?
  end

  test "validation record permission requires selected tenant and archivation" do
    record = ContractValidationRecord.new(tenant: tenants(:one))
    policy = ContractValidationRecordPolicy.new(@context, record)
    assert_not policy.index?
    assert_not policy.destroy?
    assert_not policy.refresh?
    assert_empty ContractValidationRecordPolicy::Scope.new(@context, ContractValidationRecord.all).resolve

    tenants(:one).update_column(:features, [ "archivation" ])
    assert policy.index?
    assert policy.destroy?
    assert policy.refresh?

    record.tenant = tenants(:two)
    assert_not policy.destroy?
    assert_not policy.refresh?
  end

  test "scope preserves direct tenant association and supplied constraints" do
    expected = tenants(:one).contracts.order(:id).to_a

    assert_equal expected, ContractPolicy::Scope.new(@context, Contract.all).resolve.order(:id).to_a
    assert_empty ContractPolicy::Scope.new(@context, Contract.where(tenant: tenants(:two))).resolve
    assert_empty ContractPolicy::Scope.new(nil, Contract.all).resolve
    pending_context = AuthorizationContext::PendingTenantSelection.new(user: users(:one))
    assert_empty ContractPolicy::Scope.new(pending_context, Contract.all).resolve
  end
end
