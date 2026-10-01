class Api::Federation::V1::FederationRequestInvitationPolicy < ApplicationPolicy
  def create?
    context.is_a?(AuthorizationContext::Portal) && context.portal_instance.present?
  end

  def withdraw?
    create? && record.portal_instance == context.portal_instance
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless context.is_a?(AuthorizationContext::Portal) && context.portal_instance.present?

      scope.where(portal_instance: context.portal_instance)
    end
  end
end
