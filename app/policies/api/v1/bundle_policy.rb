class Api::V1::BundlePolicy < Api::V1::ApplicationPolicy
  def create?
    authenticated?
  end

  def show?
    authenticated? && record.tenant == context.tenant
  end

  def status?
    show?
  end

  def destroy?
    show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless context.is_a?(AuthorizationContext::TenantApi) && context.tenant.present?

      scope.where(tenant: context.tenant)
    end
  end
end
