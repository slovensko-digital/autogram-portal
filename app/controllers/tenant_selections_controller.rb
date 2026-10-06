# Lets a signed-in user with several tenants pick the one to work in. The choice
# holds until sign out.
class TenantSelectionsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :ensure_tenant_selected
  before_action :redirect_when_tenant_selected

  rescue_from Pundit::NotAuthorizedError, with: :render_not_found

  def show
    authorize [ :tenant_selection, :tenant ]
    @tenants = current_user.tenants.order(plan: :asc, name: :asc)
  end

  def update
    tenant = current_user.tenants.find(params[:tenant_id])
    authorize [ :tenant_selection, tenant ]
    select_tenant!(tenant)
    redirect_to stored_location_for(:user) || dashboard_path
  end

  private

  def redirect_when_tenant_selected
    redirect_to dashboard_path if current_tenant
  end
end
