class FederationRequestPolicy < ApplicationPolicy
  def show?
    context.is_a?(AuthorizationContext::Web)
  end

  def claim?
    show? && context.user.present?
  end

  def navigation?
    claim? && context.user.federation_enabled?
  end
end
