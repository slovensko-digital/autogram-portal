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

  # The code goes to a recipient of a bundle; the context names its contract.
  def staging_mail_tenant
    Contract.find_by(uuid: params.dig(:context, :contract_id))&.tenant
  end
end
