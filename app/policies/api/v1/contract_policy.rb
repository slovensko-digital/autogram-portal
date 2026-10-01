class Api::V1::ContractPolicy < Api::V1::ApplicationPolicy
  def create?
    authenticated?
  end

  def show?
    authenticated? && (record.tenant == context.tenant || record.bundle&.tenant == context.tenant)
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

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless context.is_a?(AuthorizationContext::TenantApi) && context.tenant.present?

      scope.left_outer_joins(:bundle)
           .where("contracts.tenant_id = :tenant_id OR bundles.tenant_id = :tenant_id", tenant_id: context.tenant.id)
    end
  end
end
