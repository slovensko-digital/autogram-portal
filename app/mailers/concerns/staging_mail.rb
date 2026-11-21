# Marks every mail sent by a test instance (see StagingInstance): the subject starts with [TEST]
# and the mailer layouts add the notice to the body. Mail for addresses outside the organization
# it concerns goes to the organization owners instead and its subject names the intended
# addresses, so a test instance does not mail people who never chose to use it. Organizations with
# the staging_real_mail feature (set by administrators) send their mail as addressed.
module StagingMail
  extend ActiveSupport::Concern

  included do
    after_action :mark_staging_mail
  end

  private

  # The organization the mail concerns: its members get their mail, mail for anyone else goes to
  # its owners. Mail without one (sign-in links and other account mail) goes as addressed.
  def staging_mail_tenant
  end

  def mark_staging_mail
    return unless StagingInstance.active?

    prefix = redirect_staging_mail || "[TEST]"
    message.subject = "#{prefix} #{message.subject}" if message.subject.present?
  end

  # Returns the subject prefix naming the intended addresses when the mail is redirected.
  def redirect_staging_mail
    tenant = staging_mail_tenant
    return unless tenant && StagingInstance.redirect_mail_for?(tenant)

    member_emails = tenant.users.pluck(:email).map(&:downcase)
    outsiders = Array(message.to).reject { member_emails.include?(it.downcase) }
    return if outsiders.empty?

    message.to = (Array(message.to) - outsiders) | tenant.owners.pluck(:email)
    I18n.t("staging_mail.redirected_subject", addresses: outsiders.join(", "))
  end
end
