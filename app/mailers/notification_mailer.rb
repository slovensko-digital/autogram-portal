class NotificationMailer < ApplicationMailer
  before_action { @user = params[:user] }
  before_action :set_locale

  def contract_signed(contract)
    @contract = contract
    @signature = contract.validation_result.signatures.last
    mail(to: @user.email, subject: 'Your contract has been signed')
  end

  private

  def set_locale
    I18n.locale = @user&.locale || I18n.default_locale
  end
end
