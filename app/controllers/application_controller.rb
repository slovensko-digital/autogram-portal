class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_user

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

  def set_user
    @user = User.first_or_create!(email: "anonymous@example.com", name: "Anonymous User")
  end
end
