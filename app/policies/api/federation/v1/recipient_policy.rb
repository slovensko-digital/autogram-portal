class Api::Federation::V1::RecipientPolicy < ApplicationPolicy
  def show?
    portal? && record.federated_recipient? && record.portal_instance == context.portal_instance
  end

  def claim?
    show?
  end
end
