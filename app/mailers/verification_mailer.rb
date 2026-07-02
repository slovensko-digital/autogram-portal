class VerificationMailer < ApplicationMailer
  before_action :set_locale

  def otp_code
    @code = params[:code]
    @app_host = ENV["APP_HOST"]

    mail(
      to: params[:email],
      subject: I18n.t("verification_mailer.otp_code.subject")
    )
  end

  private

  def set_locale
    I18n.locale = params[:locale] || I18n.default_locale
  end
end
