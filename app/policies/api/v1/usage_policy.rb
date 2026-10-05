class Api::V1::UsagePolicy < Api::V1::ApplicationPolicy
  def show?
    tenant_api?
  end
end
