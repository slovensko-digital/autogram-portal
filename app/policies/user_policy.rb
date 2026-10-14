class UserPolicy < ApplicationPolicy
  def manage_account?
    signed_in? && context.user == record
  end
end
