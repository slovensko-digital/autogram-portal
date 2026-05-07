require "test_helper"

class NotificationMailerTest < ActionMailer::TestCase
  test "signature requested escapes bundle note HTML" do
    bundle = create_bundle_with_note("<b>Phish</b>\nline2")

    mail = NotificationMailer.with(user: users(:two)).signature_requested(bundle)
    body = mail.html_part ? mail.html_part.body.encoded : mail.body.encoded

    assert_includes body, "&lt;b&gt;Phish&lt;/b&gt;"
    assert_includes body, "line2"
    assert_not_includes body, "<b>Phish</b>"
  end

  test "signature withdrawn includes apology and no action link" do
    bundle = create_bundle_with_note("test")
    recipient = bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(6)}@example.com", locale: "en")

    mail = NotificationMailer.with(user: recipient).signature_withdrawn(bundle)
    body = mail.html_part ? mail.html_part.body.encoded : mail.body.encoded

    assert_equal I18n.t("notification_mailer.signature_withdrawn.subject", locale: :en), mail.subject
    assert_includes body, I18n.t("notification_mailer.signature_withdrawn.apology", locale: :en)
    assert_not_includes body, "View bundle"
  end

  private

  def create_bundle_with_note(note)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "mail-test.pdf",
      content_type: "application/pdf"
    )

    contract = Contract.new(
      user: users(:one),
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )
    contract.save!

    bundle = Bundle.new(
      author: users(:one),
      uuid: SecureRandom.uuid,
      note: note,
      contracts: [ contract ]
    )
    bundle.save!

    bundle
  end
end
