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

  # Approving or returning scans of documents signed on paper, and downloading them.
  def review_paper_signatures?
    manage?
  end

  class Scope < TenantScope
  end
end
