class UserPolicy < ApplicationPolicy
  def manage_account?
    signed_in? && context.user == record
  end

  def edit_features?
    manage_account? && record.admin?
  end
end
