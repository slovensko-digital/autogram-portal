class BundlePolicy < ApplicationPolicy
  def index?
    context.is_a?(AuthorizationContext::Web) && context.user.present? && context.tenant.present?
  end

  def manage?
    index? && record.managed_by?(context.tenant)
  end

  def show?
    manage?
  end

  def update?
    manage?
  end

  def destroy?
    manage?
  end

  def manage_recipients?
    manage?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless context.is_a?(AuthorizationContext::Web) && context.user.present? && context.tenant.present?

      scope.where(tenant: context.tenant)
    end
  end
end
