class Received::FederationRequestInvitationPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve
      signed_in? ? scope.for_user(context.user) : scope.none
    end
  end
end
