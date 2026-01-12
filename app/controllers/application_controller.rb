class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_locale

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

  private

  def set_locale
    I18n.locale = current_user.try(:locale) || session[:locale] || I18n.default_locale
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
  end
end
