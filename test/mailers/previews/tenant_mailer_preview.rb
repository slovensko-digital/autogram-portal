# Preview all emails at http://localhost:3000/rails/mailers/tenant_mailer
class TenantMailerPreview < ActionMailer::Preview
  def invitation
    membership = Membership.first
    TenantMailer.with(membership: membership, locale: params[:locale]).invitation
  end
end
