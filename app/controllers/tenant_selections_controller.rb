# Finishes signing in: a user with several tenants picks the one to work in, and
# a user without any tenant can create a personal one. Until then the user is
# not signed in, only remembered as pending for a short while. The choice holds
# until sign out.
class TenantSelectionsController < ApplicationController
  PENDING_FOR = 15.minutes

  skip_before_action :ensure_tenant_selected
  before_action :redirect_when_signed_in
  before_action :set_pending_user
  prepend_after_action :pundit_reset!, only: [ :update, :create ]

  rescue_from Pundit::NotAuthorizedError, with: :render_not_found

  def show
    authorize [ :tenant_selection, :tenant ]
    @tenants = @user.tenants.order(:name)
  end

  def update
    tenant = @user.tenants.find(params[:tenant_id])
    authorize [ :tenant_selection, tenant ]
    complete_sign_in(tenant)
  end

  def create
    if @user.tenants.exists?
      skip_authorization
      return redirect_to tenant_selection_path
    end

    authorize [ :tenant_selection, :tenant ]
    complete_sign_in(Tenant.create_personal_for!(@user))
  end

  private

  def pundit_user
    return super if current_user

    AuthorizationContext::PendingTenantSelection.new(user: @user)
  end

  def redirect_when_signed_in
    return unless current_user
    return redirect_to dashboard_path if current_tenant

    defer_sign_in_until_tenant_selected!
  end

  def set_pending_user
    pending_since = session[:pending_tenant_user_at].to_i
    @user = User.find_by(id: session[:pending_tenant_user_id]) if pending_since > PENDING_FOR.ago.to_i
    return if @user

    clear_pending_user
    redirect_to new_user_session_path
  end

  def complete_sign_in(tenant)
    clear_pending_user
    sign_in(:user, @user)
    select_tenant!(tenant)
    redirect_to session.delete(:tenant_return_to) || dashboard_path, notice: t("devise.sessions.signed_in")
  end

  def clear_pending_user
    session.delete(:pending_tenant_user_id)
    session.delete(:pending_tenant_user_at)
  end
end
