module VerifiesAltchaCaptcha
  extend ActiveSupport::Concern

  included do
    before_action :verify_altcha_captcha, only: [ :create ]
  end

  private

  def verify_altcha_captcha
    return unless Rails.env.production? || ENV["ALTCHA_HMAC_KEY"].present?

    payload = params[:altcha].presence
    return if payload && AltchaService.verify_solution(payload, hmac_key: altcha_hmac_key)

    redirect_to altcha_failed_redirect_path, alert: t("devise.registrations.captcha_invalid")
  end

  def altcha_failed_redirect_path
    helper = "new_#{controller_name.singularize}_path"

    if respond_to?(helper, true)
      public_send(helper, resource_name)
    else
      main_app.root_path
    end
  end

  def altcha_hmac_key
    Rails.application.credentials.altcha_hmac_key.presence ||
      ENV.fetch("ALTCHA_HMAC_KEY") { raise "ALTCHA_HMAC_KEY is not set" }
  end
end
