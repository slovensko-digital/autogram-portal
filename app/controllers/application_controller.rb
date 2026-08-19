class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_locale
  before_action :enforce_current_policy_consent, if: :user_signed_in?
  helper_method :current_tenant, :current_tenant_membership, :current_tenant_admin?

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::RoutingError, with: :render_not_found

  def render_not_found
    respond_to do |format|
      format.html { render file: Rails.root.join("public", "404.html"), status: :not_found, layout: false }
      format.json { render json: { error: "Not Found" }, status: :not_found }
    end
  end

  # Chrome DevTools configuration endpoint
  def devtools_config
    config = {
      version: "1.0",
      application: {
        name: "Autogram Portal",
        version: (Rails.application.config.version rescue "dev"),
        environment: Rails.env
      },
      debug: {
        enabled: Rails.env.development?,
        endpoints: Rails.env.development? ? {
          health: url_for(controller: "rails/health", action: "show", only_path: false),
          routes: Rails.env.development? ? "#{request.base_url}/rails/info/routes" : nil
        }.compact : {}
      },
      features: {
        pwa: true,
        signing: true
      }
    }

    render json: config
  end

  def current_tenant
    return unless user_signed_in?

    @current_tenant ||= begin
      tenant = current_user.tenants.find_by(id: current_user.current_tenant_id)
      tenant ||= current_user.tenants.order(:id).first
      current_user.update_column(:current_tenant_id, tenant.id) if tenant && current_user.current_tenant_id != tenant.id
      tenant
    end
  end

  def current_tenant_membership
    return unless current_tenant

    @current_tenant_membership ||= current_user.tenant_users.find_by(tenant: current_tenant)
  end

  def current_tenant_admin?
    current_tenant_membership&.admin? || false
  end

  private

  def set_locale
    I18n.locale = params[:locale] || session[:locale] || cookies[:locale] || current_user.try(:locale) || I18n.default_locale
    session[:locale] = I18n.locale
    cookies[:locale] = { value: I18n.locale, expires: 1.year.from_now, secure: Rails.env.production?, httponly: true }
  end

  def enforce_current_policy_consent
    return if devise_controller?
    return if current_user.accepted_current_policies?

    redirect_to new_consent_url
  end

  def no_header
    @no_header = true
  end

  def no_footer
    @no_footer = true
  end

  def no_flash
    @no_flash = true
  end

  def allow_iframe
    response.headers.except! "X-Frame-Options"

    if params[:iframe].present?
      no_header
      no_footer
      no_flash
    end
  end
end
