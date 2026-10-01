class AdminPolicy < ApplicationPolicy
  def access?
    context.is_a?(AuthorizationContext::Web) && context.user.present? && context.user.admin?
  end
end
