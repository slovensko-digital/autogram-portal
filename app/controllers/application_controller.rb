class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_locale
  before_action :enforce_current_policy_consent, if: :user_signed_in?
  before_action :ensure_tenant_selected, if: :user_signed_in?
  before_action :skip_authorization, only: [ :devtools_config ]
  after_action :verify_authorized
  after_action :verify_policy_scoped, if: -> { action_name == "index" }

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::RoutingError, with: :render_not_found

  helper_method :current_tenant

  def render_not_found
    respond_to do |format|
      format.html { render "errors/show", layout: "errors", status: :not_found, locals: { status: 404 } }
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

  protected

  # The tenant the signed-in user currently works in. Lists and newly created
  # records are scoped to it. Users with several tenants pick one after signing
  # in; a single tenant is picked for them.
  def current_tenant
    return unless current_user

    @current_tenant ||= resolve_current_tenant
  end

  # Signed-in users work in a tenant. Until they pick one they are sent to the
  # tenant selection page, which then returns them to the page they asked for.
  def ensure_tenant_selected
    return if devise_controller? || current_tenant

    store_location_for(:user, request.fullpath) if request.get? && request.format.html?
    flash.keep
    redirect_to tenant_selection_path
  end

  # Picks one of the user's tenants for the rest of the session; it stays until
  # sign out.
  def select_tenant!(tenant)
    session[:current_tenant_id] = tenant.id
    current_user.update_column(:last_tenant_id, tenant.id) if current_user.last_tenant_id != tenant.id
    @current_tenant = tenant
  end

  # A record of another tenant the user belongs to: they have to sign in to that
  # tenant to work with it. Returns whether it redirected.
  def redirect_for_other_tenant(record)
    tenant = record.try(:tenant)
    return false unless current_user&.member_of?(tenant)

    redirect_to dashboard_path, alert: t("tenants.alerts.other_tenant_record", name: tenant.name)
    true
  end

  def render_tenant_record_denial(error)
    render_not_found unless redirect_for_other_tenant(error.record)
  end

  def tenant_settings_path
    edit_user_registration_path(anchor: "organization")
  end

  def after_sign_in_path_for(resource)
    stored_location_for(resource) || pending_contract_path || super
  end

  private

  def pundit_user
    AuthorizationContext::Web.new(user: current_user, tenant: current_tenant)
  end

  def resolve_current_tenant
    tenants = current_user.tenants
    tenant = tenants.find_by(id: session[:current_tenant_id]) if session[:current_tenant_id]
    tenant ||= tenants.first if tenants.one?
    select_tenant!(tenant) if tenant
  end

  def pending_contract_path
    contract_uuid = session[:pending_contract_claim_uuid]
    contract_path(contract_uuid) if contract_uuid.present?
  end

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
