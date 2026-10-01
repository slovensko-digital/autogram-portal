class ContractValidationRecordPolicy < ApplicationPolicy
  def index?
    context.is_a?(AuthorizationContext::Web) && context.user.present? && context.tenant&.archivation_enabled?
  end

  def destroy?
    index? && record.tenant == context.tenant
  end

  def refresh?
    destroy?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless context.is_a?(AuthorizationContext::Web) && context.user.present? && context.tenant&.archivation_enabled?

      scope.where(tenant: context.tenant)
    end
  end
end
