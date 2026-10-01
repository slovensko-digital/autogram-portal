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

  # Raised for a record of another tenant the user belongs to; they have to sign
  # in to that tenant to work with it.
  class OtherTenantRecord < StandardError
    attr_reader :tenant

    def initialize(tenant)
      @tenant = tenant
      super("Record belongs to tenant #{tenant.id}")
    end
  end

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from OtherTenantRecord, with: :render_other_tenant_record

  helper_method :current_tenant
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

  protected

  # The tenant the signed-in user currently works in. Lists and newly created
  # records are scoped to it. Users with several tenants pick one after signing
  # in; a single tenant is picked for them.
  def current_tenant
    return unless current_user
    return @current_tenant if defined?(@current_tenant) && @current_tenant

    @current_tenant = resolve_current_tenant
  end

  # A user is signed in only together with a tenant. Someone who authenticated
  # but still has to pick one (or create one) is signed out again and waits on
  # the tenant selection page, which completes the sign-in.
  def ensure_tenant_selected
    return if devise_controller? || params[:iframe].present? || current_tenant

    session[:tenant_return_to] = request.fullpath if request.get? && request.format.html?
    defer_sign_in_until_tenant_selected!
    redirect_to tenant_selection_path
  end

  def defer_sign_in_until_tenant_selected!
    session[:pending_tenant_user_id] = current_user.id
    session[:pending_tenant_user_at] = Time.current.to_i
    flash.delete(:notice)
    sign_out(:user)
    pundit_reset!
  end

  # Picks the tenant for the rest of the session; it stays until sign out.
  def select_tenant!(tenant)
    return unless current_user&.member_of?(tenant)

    session[:current_tenant_id] = tenant.id
    current_user.update_column(:last_tenant_id, tenant.id) if current_user.last_tenant_id != tenant.id
    @current_tenant = tenant
  end

  def render_other_tenant_record(error)
    redirect_to dashboard_path, alert: t("tenants.alerts.other_tenant_record", name: error.tenant.name)
  end

  def redirect_for_other_tenant(record)
    owning_tenant = record.respond_to?(:owning_tenant) ? record.owning_tenant : record.try(:tenant)
    return false unless current_user&.member_of?(owning_tenant)

    render_other_tenant_record(OtherTenantRecord.new(owning_tenant))
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
    return unless tenant

    session[:current_tenant_id] = tenant.id
    current_user.update_column(:last_tenant_id, tenant.id) if current_user.last_tenant_id != tenant.id
    tenant
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
