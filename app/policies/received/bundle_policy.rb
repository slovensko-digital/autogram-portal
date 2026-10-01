class Received::BundlePolicy < ApplicationPolicy
  def index?
    context.is_a?(AuthorizationContext::Web) && context.user.present?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless context.is_a?(AuthorizationContext::Web) && context.user.present?

      scope.recipient_user(context.user)
    end
  end
end
