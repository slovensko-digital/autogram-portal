class AdminPolicy < ApplicationPolicy
  def access?
    signed_in? && context.user.admin?
  end
end
