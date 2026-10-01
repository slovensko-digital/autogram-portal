require "test_helper"

class ApiPolicyTest < ActiveSupport::TestCase
  setup do
    @context = AuthorizationContext::TenantApi.new(tenant: tenants(:one))
  end

  test "API contract and document access follows the contract tenant" do
    contract = Contract.new(tenant: tenants(:one), bundle: bundles(:one))
    document = Document.new(contract: contract)

    assert Api::V1::ContractPolicy.new(@context, contract).show?
    assert Api::V1::ContractPolicy.new(@context, contract).destroy?
    assert Api::V1::DocumentPolicy.new(@context, document).show?

    other_context = AuthorizationContext::TenantApi.new(tenant: tenants(:two))
    assert_not Api::V1::ContractPolicy.new(other_context, contract).show?
    assert_not Api::V1::DocumentPolicy.new(other_context, document).show?
  end

  test "bundle policies ignore public visibility and user admin privileges" do
    bundle = Bundle.new(tenant: tenants(:two), publicly_visible: true)
    assert_not Api::V1::BundlePolicy.new(@context, bundle).show?
    assert_not Api::V1::BundlePolicy.new(@context, bundle).destroy?
  end

  test "authenticated tenant API context permits creation without a user" do
    assert Api::V1::ContractPolicy.new(@context, Contract).create?
    assert Api::V1::BundlePolicy.new(@context, Bundle).create?
    assert Api::V1::HelloPolicy.new(@context, :hello).show_auth?
  end

  test "orphan documents are not API accessible" do
    assert_not Api::V1::DocumentPolicy.new(@context, Document.new).show?
  end

  test "web contexts cannot impersonate tenant API" do
    contexts = [
      nil,
      AuthorizationContext::TenantApi.new(tenant: nil),
      AuthorizationContext::Web.new(user: users(:one), tenant: tenants(:one)),
      AuthorizationContext::Web.new(user: users(:one), tenant: nil)
    ]
    contract = Contract.new(tenant: tenants(:one))
    document = Document.new(contract: contract)

    contexts.each do |context|
      assert_not Api::V1::ContractPolicy.new(context, Contract).create?
      assert_not Api::V1::ContractPolicy.new(context, contract).show?
      assert_not Api::V1::DocumentPolicy.new(context, document).show?
      assert_not Api::V1::BundlePolicy.new(context, bundles(:one)).show?
      assert_not Api::V1::HelloPolicy.new(context, :hello).show_auth?
      assert_empty Api::V1::ContractPolicy::Scope.new(context, Contract.all).resolve
      assert_empty Api::V1::DocumentPolicy::Scope.new(context, Document.all).resolve
      assert_empty Api::V1::BundlePolicy::Scope.new(context, Bundle.all).resolve
    end
  end

  test "API scopes retain constrained input and the tenant ownership" do
    contract = contracts(:one)

    assert_includes Api::V1::ContractPolicy::Scope.new(@context, Contract.all).resolve, contract
    assert_not_includes Api::V1::ContractPolicy::Scope.new(@context, Contract.all).resolve, contracts(:two)
    assert_empty Api::V1::ContractPolicy::Scope.new(@context, Contract.where(id: nil)).resolve
    assert_empty Api::V1::BundlePolicy::Scope.new(@context, Bundle.where(id: bundles(:two).id)).resolve
  end

  test "document scopes share contract ownership without widening the input scope" do
    document = documents(:one)

    assert_includes Api::V1::DocumentPolicy::Scope.new(@context, Document.all).resolve, document
    other_context = AuthorizationContext::TenantApi.new(tenant: tenants(:two))
    assert_not_includes Api::V1::DocumentPolicy::Scope.new(other_context, Document.all).resolve, document

    assert_empty Api::V1::DocumentPolicy::Scope.new(@context, Document.where(id: nil)).resolve

    document.update_column(:contract_id, nil)
    assert_empty Api::V1::DocumentPolicy::Scope.new(@context, Document.where(id: document.id)).resolve
  end
end
