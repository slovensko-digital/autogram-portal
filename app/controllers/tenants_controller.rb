class TenantsController < ApplicationController
  before_action :authenticate_user!

  def switch
    tenant = current_user.tenants.find(params[:tenant_id])
    current_user.update_column(:current_tenant_id, tenant.id)
    current_user.association(:current_tenant).reset

    redirect_to dashboard_path
  end

  def update_settings
    return head :forbidden unless current_tenant_admin?

    if current_tenant.update(tenant_settings_params)
      redirect_to edit_user_registration_path, notice: t(".success")
    else
      redirect_to edit_user_registration_path, alert: current_tenant.errors.full_messages.to_sentence
    end
  end

  private

  def tenant_settings_params
    params.require(:tenant).permit(:api_token_public_key, features: [])
  end
end
