class ContractValidationRecordPolicy < ApplicationPolicy
  def index?
    in_tenant? && context.tenant.archivation_enabled?
  end

  def destroy?
    index? && record.tenant == context.tenant
  end

  def refresh?
    destroy?
  end

  class Scope < TenantScope
    def resolve
      in_tenant? && context.tenant.archivation_enabled? ? super : scope.none
    end
  end
end
