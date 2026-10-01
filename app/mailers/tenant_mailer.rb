class TenantMailer < ApplicationMailer
  before_action do
    @membership = params[:membership]
    @tenant = @membership.tenant
    @user = @membership.user
  end
  before_action :set_locale

  default to: -> { @user.email }

  def invitation
    @url = @user.confirmed? ? dashboard_url : user_confirmation_url(confirmation_token: @user.confirmation_token)
    mail(subject: I18n.t("tenant_mailer.invitation.subject", tenant: @tenant.name))
  end

  private

  def set_locale
    I18n.locale = params[:locale] || @user.locale.presence || I18n.default_locale
  end
end
