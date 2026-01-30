class NotificationMailer < ApplicationMailer
  before_action { @user = params[:user] || params[:recipient] }
  before_action :set_locale
  default to: -> { @user.email }

  def contract_signed(contract, signer)
    @contract = contract
    @signature = contract.validation_result.signatures.last
    @signer = signer
    mail(subject: I18n.t("notification_mailer.contract_signed.subject"))
  end

  def bundle_contract_signed(bundle, contract, signer)
    @bundle = bundle
    @contract = contract
    mail(subject: I18n.t("notification_mailer.bundle_contract_signed.subject"))
  end

  def bundle_completed(bundle)
    @bundle = bundle
    mail(subject: I18n.t("notification_mailer.bundle_completed.subject"))
  end

  def signature_requested(bundle)
    @bundle = bundle
    mail(subject: I18n.t("notification_mailer.signature_requested.subject"))
  end

  private

  def set_locale
    I18n.locale = @user&.locale || I18n.default_locale
  end
end
