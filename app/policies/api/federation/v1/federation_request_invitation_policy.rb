class Api::Federation::V1::FederationRequestInvitationPolicy < ApplicationPolicy
  def create?
    portal?
  end

  def withdraw?
    create? && record.portal_instance == context.portal_instance
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      portal? ? scope.where(portal_instance: context.portal_instance) : scope.none
    end
  end
end
