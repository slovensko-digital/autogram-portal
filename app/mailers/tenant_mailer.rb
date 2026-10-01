class TenantMailer < ApplicationMailer
  before_action do
    @membership = params[:membership]
    @tenant = @membership.tenant
    @user = @membership.user
    I18n.locale = @user.locale.presence || I18n.default_locale
  end

  default to: -> { @user.email }

  def invitation
    @url = @user.confirmed? ? dashboard_url : user_confirmation_url(confirmation_token: @user.confirmation_token)
    mail(subject: I18n.t("tenant_mailer.invitation.subject", tenant: @tenant.name))
  end
end
