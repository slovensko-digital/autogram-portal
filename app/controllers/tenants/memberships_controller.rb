class Tenants::MembershipsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_tenant
  before_action :ensure_owner!

  def create
    email = params.dig(:membership, :email).to_s.strip.downcase
    return redirect_to tenant_settings_path, alert: t(".email_missing") if email.blank?

    membership = ActiveRecord::Base.transaction do
      user = User.find_or_invite!(email, locale: current_user.locale)
      @tenant.add_member!(user, role: params.dig(:membership, :role).presence_in(Membership.roles.keys) || "member")
    end

    TenantMailer.with(membership: membership).invitation.deliver_later
    redirect_to tenant_settings_path, notice: t(".success", email: email)
  rescue ActiveRecord::RecordInvalid => e
    redirect_to tenant_settings_path, alert: e.record.errors.full_messages.to_sentence
  end

  def destroy
    membership = @tenant.memberships.find(params[:id])

    if membership.destroy
      redirect_to tenant_settings_path, notice: t(".success", email: membership.user.email)
    else
      redirect_to tenant_settings_path, alert: membership.errors.full_messages.to_sentence
    end
  end

  private

  def set_tenant
    @tenant = current_tenant
  end

  def ensure_owner!
    redirect_to tenant_settings_path, alert: t("tenants.alerts.owner_required") unless @tenant.owner?(current_user)
  end
end
