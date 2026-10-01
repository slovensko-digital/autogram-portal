class UserPolicy < ApplicationPolicy
  def manage_account?
    context.is_a?(AuthorizationContext::Web) && context.user.present? && context.user == record
  end

  def edit_features?
    manage_account? && record.admin?
  end
end
