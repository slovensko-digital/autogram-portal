class TenantsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_tenant
  before_action :authorize_tenant!

  rescue_from Pundit::NotAuthorizedError, with: :render_owner_required

  def update
    # Only the API key; the name and plan are managed by administrators.
    if @tenant.update(permitted_attributes(@tenant))
      redirect_to tenant_settings_path, notice: t(".success")
    else
      redirect_to tenant_settings_path, alert: @tenant.errors.full_messages.to_sentence
    end
  end

  def leave
    membership = @tenant.memberships.find_by!(user: current_user)

    if membership.destroy
      current_user.update_column(:last_tenant_id, nil)
      session.delete(:current_tenant_id)
      redirect_to dashboard_path, notice: t(".success", name: @tenant.name)
    else
      redirect_to tenant_settings_path, alert: membership.errors.full_messages.to_sentence
    end
  end

  private

  def set_tenant
    @tenant = current_tenant
  end

  def authorize_tenant!
    authorize @tenant
  end

  def render_owner_required
    redirect_to tenant_settings_path, alert: t("tenants.alerts.owner_required")
  end
end
