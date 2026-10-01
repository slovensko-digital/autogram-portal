class FederationRequestPolicy < ApplicationPolicy
  def claim?
    signed_in?
  end

  def navigation?
    signed_in? && context.user.federation_enabled?
  end
end
