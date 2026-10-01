class Api::V1::ContractPolicy < Api::V1::ApplicationPolicy
  def create?
    tenant_api?
  end

  def show?
    tenant_api? && record.tenant == context.tenant
  end

  def status?
    show?
  end

  def signed_document?
    show?
  end

  def destroy?
    show?
  end

  class Scope < Api::V1::ApplicationPolicy::TenantScope
  end
end
