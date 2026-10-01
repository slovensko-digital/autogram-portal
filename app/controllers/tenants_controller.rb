class TenantsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_tenant, only: [ :update, :leave ]
  before_action :ensure_owner!, only: [ :update ]

  def update
    if @tenant.update(tenant_params)
      redirect_to tenant_settings_path, notice: t(".success")
    else
      redirect_to tenant_settings_path, alert: @tenant.errors.full_messages.to_sentence
    end
  end

  def leave
    membership = @tenant.memberships.find_by!(user: current_user)

    if membership.destroy
      current_user.update_column(:last_tenant_id, nil)
      sign_out(current_user)
      redirect_to new_user_session_path, notice: t(".success", name: @tenant.name)
    else
      redirect_to tenant_settings_path, alert: membership.errors.full_messages.to_sentence
    end
  end

  private

  def set_tenant
    @tenant = current_tenant
  end

  def ensure_owner!
    redirect_to tenant_settings_path, alert: t("tenants.alerts.owner_required") unless @tenant.owner?(current_user)
  end

  def tenant_params
    # The name and plan are managed by administrators only.
    return {} unless @tenant.api_enabled?

    params.require(:tenant).permit(:api_token_public_key)
  end
end
