class Api::Federation::V1::RecipientPolicy < ApplicationPolicy
  def show?
    context.is_a?(AuthorizationContext::Portal) && context.portal_instance.present? &&
      record.federated_recipient? && record.portal_instance == context.portal_instance
  end

  def claim?
    show?
  end
end
