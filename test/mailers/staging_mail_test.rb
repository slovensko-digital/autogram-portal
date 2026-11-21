require "test_helper"
require_relative "../support/staging_instance_helper"

# A test instance sends mail meant for people outside an organization to its owners instead.
class StagingMailTest < ActionMailer::TestCase
  include StagingInstanceHelper

  setup do
    @owner = users(:one)
    @owner.update_columns(email: "owner@example.com")
    @tenant = tenants(:one)
    @bundle = create_bundle(@tenant)
    @subject = I18n.t("notification_mailer.signature_requested.subject")
  end

  test "mail for a recipient goes to the owner and names the recipient" do
    recipient = @bundle.recipients.create!(email: "Signer@Example.com", locale: "sk")

    mail = NotificationMailer.with(recipient: recipient).signature_requested(@bundle)

    assert_equal [ "owner@example.com" ], mail.to
    assert_equal "[TEST pre Signer@Example.com] #{@subject}", mail.subject
  end

  test "the subject names the recipient in the recipient's language" do
    recipient = @bundle.recipients.create!(email: "signer@example.com", locale: "en")

    mail = NotificationMailer.with(recipient: recipient).signature_requested(@bundle)

    assert_equal [ "owner@example.com" ], mail.to
    assert_equal "[TEST for signer@example.com] #{I18n.t("notification_mailer.signature_requested.subject", locale: :en)}", mail.subject
  end

  test "mail for a member of the organization goes as addressed" do
    recipient = @bundle.recipients.create!(email: "OWNER@example.com", locale: "sk")

    mail = NotificationMailer.with(recipient: recipient).signature_requested(@bundle)

    assert_equal [ "OWNER@example.com" ], mail.to
    assert_equal "[TEST] #{@subject}", mail.subject
  end

  test "all owners of an organization get the mail" do
    @tenant.update!(plan: :pro)
    co_owner = users(:two)
    co_owner.update_columns(email: "co-owner@example.com")
    @tenant.memberships.create!(user: co_owner, role: :owner)
    recipient = @bundle.recipients.create!(email: "signer@example.com", locale: "sk")

    mail = NotificationMailer.with(recipient: recipient).signature_withdrawn(@bundle)

    assert_equal [ "co-owner@example.com", "owner@example.com" ], mail.to.sort
  end

  test "verification codes for a recipient go to the owner" do
    recipient = @bundle.recipients.create!(email: "signer@example.com", locale: "sk")

    mail = VerificationMailer.with(email: recipient.email, code: "123456", locale: "sk",
                                   context: { contract_id: @bundle.contracts.first.uuid, recipient_id: recipient.uuid }).otp_code

    assert_equal [ "owner@example.com" ], mail.to
    assert_equal "[TEST pre signer@example.com] #{I18n.t("verification_mailer.otp_code.subject")}", mail.subject
  end

  test "an invitation goes to the invited member" do
    @tenant.update!(plan: :pro)
    invited = User.find_or_invite!("invited@example.com")
    membership = @tenant.memberships.create!(user: invited)

    mail = TenantMailer.with(membership: membership).invitation

    assert_equal [ "invited@example.com" ], mail.to
    assert mail.subject.start_with?("[TEST] ")
  end

  test "an organization with real emails sends mail as addressed" do
    @tenant.update!(features: [ "staging_real_mail" ])
    recipient = @bundle.recipients.create!(email: "signer@example.com", locale: "sk")

    mail = NotificationMailer.with(recipient: recipient).signature_requested(@bundle)

    assert_equal [ "signer@example.com" ], mail.to
    assert_equal "[TEST] #{@subject}", mail.subject
  end

  test "production sends mail as addressed" do
    ENV.delete("PRODUCTION_URL")
    recipient = @bundle.recipients.create!(email: "signer@example.com", locale: "sk")

    mail = NotificationMailer.with(recipient: recipient).signature_requested(@bundle)

    assert_equal [ "signer@example.com" ], mail.to
    assert_equal @subject, mail.subject
  end

  private

  def create_bundle(tenant)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 staging mail"), filename: "staging.pdf", content_type: "application/pdf")
    contract = Contract.new(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )

    Bundle.create!(tenant: tenant, name: "Staging bundle", contracts: [ contract ])
  end
end
