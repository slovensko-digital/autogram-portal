class Api::V1::ApplicationPolicy < ApplicationPolicy
  private

  def authenticated?
    context.is_a?(AuthorizationContext::TenantApi) && context.tenant.present?
  end
end
