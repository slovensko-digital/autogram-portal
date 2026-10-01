class Api::V1::ApplicationPolicy < ApplicationPolicy
  # Records of the tenant the API token was issued for.
  class TenantScope < ApplicationPolicy::Scope
    def resolve
      tenant_api? ? scope.where(tenant: context.tenant) : scope.none
    end
  end
end
