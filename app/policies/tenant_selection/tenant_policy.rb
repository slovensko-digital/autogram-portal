class TenantSelection::TenantPolicy < ApplicationPolicy
  def show?
    pending_user?
  end

  def update?
    pending_user? && record.is_a?(Tenant) && context.user.member_of?(record)
  end

  def create?
    pending_user? && context.user.tenants.none?
  end

  private

  def pending_user?
    context.is_a?(AuthorizationContext::PendingTenantSelection) && context.user.present?
  end
end
