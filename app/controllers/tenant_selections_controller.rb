# Lets a signed-in user with several tenants pick the one to work in, and a
# user without any tenant create a personal one. The choice holds until sign out.
class TenantSelectionsController < ApplicationController
  before_action :authenticate_user!
  skip_before_action :ensure_tenant_selected
  before_action :redirect_when_tenant_selected

  rescue_from Pundit::NotAuthorizedError, with: :render_not_found

  def show
    authorize [ :tenant_selection, :tenant ]
    @tenants = current_user.tenants.order(:name)
  end

  def update
    tenant = current_user.tenants.find(params[:tenant_id])
    authorize [ :tenant_selection, tenant ]
    complete_selection(tenant)
  end

  def create
    authorize [ :tenant_selection, :tenant ]
    complete_selection(Tenant.create_personal_for!(current_user))
  end

  private

  def redirect_when_tenant_selected
    redirect_to dashboard_path if current_tenant
  end

  def complete_selection(tenant)
    select_tenant!(tenant)
    redirect_to stored_location_for(:user) || dashboard_path
  end
end
