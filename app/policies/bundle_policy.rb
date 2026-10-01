class BundlePolicy < ApplicationPolicy
  def index?
    in_tenant?
  end

  def manage?
    in_tenant? && record.managed_by?(context.tenant)
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

  class Scope < TenantScope
  end
end
