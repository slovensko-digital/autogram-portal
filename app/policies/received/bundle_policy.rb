class Received::BundlePolicy < ApplicationPolicy
  def index?
    signed_in?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      signed_in? ? scope.recipient_user(context.user) : scope.none
    end
  end
end
