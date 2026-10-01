class DashboardPolicy < ApplicationPolicy
  def index?
    context.is_a?(AuthorizationContext::Web) && context.user.present? && context.tenant.present?
  end
end
