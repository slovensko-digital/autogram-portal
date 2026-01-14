class NotificationMailer < ApplicationMailer
  before_action { @user = params[:user] }
  before_action :set_locale
  default to: -> { @user.email }

  def contract_signed(contract)
    @contract = contract
    @signature = contract.validation_result.signatures.last
    mail(subject: I18n.t("notification_mailer.contract_signed.subject"))
  end

  def bundle_completed(bundle)
    @bundle = bundle
    mail(subject: I18n.t("notification_mailer.bundle_completed.subject"))
  end

  private

  def set_locale
    I18n.locale = @user&.locale || I18n.default_locale
  end
end
