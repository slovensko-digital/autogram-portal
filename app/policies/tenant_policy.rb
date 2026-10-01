class TenantPolicy < ApplicationPolicy
  def update?
    selected_tenant? && record.owner?(context.user)
  end

  def manage_memberships?
    update?
  end

  def edit_api_key?
    update? && record.api_enabled?
  end

  def leave?
    selected_tenant? && context.user.member_of?(record)
  end

  def permitted_attributes_for_update
    edit_api_key? ? [ :api_token_public_key ] : []
  end

  private

  def selected_tenant?
    context.is_a?(AuthorizationContext::Web) && context.user.present? && record.present? && context.tenant == record
  end
end
