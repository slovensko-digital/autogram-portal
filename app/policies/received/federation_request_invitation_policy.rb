class Received::FederationRequestInvitationPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless context.is_a?(AuthorizationContext::Web) && context.user.present?

      scope.for_user(context.user)
    end
  end
end
