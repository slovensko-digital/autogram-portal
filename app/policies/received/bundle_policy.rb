class Received::BundlePolicy < ApplicationPolicy
  def index?
    signed_in?
  end

  # Signing everything awaiting the user in one Autogram batch.
  def autogram_batch?
    signed_in?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      signed_in? ? scope.recipient_user(context.user) : scope.none
    end
  end
end
