class TenantSelection::TenantPolicy < ApplicationPolicy
  def show?
    choosing_tenant?
  end

  def update?
    choosing_tenant? && record.is_a?(Tenant) && context.user.member_of?(record)
  end

  private

  # The tenant is chosen once per sign-in and cannot be switched afterwards.
  def choosing_tenant?
    signed_in? && context.tenant.nil?
  end
end
