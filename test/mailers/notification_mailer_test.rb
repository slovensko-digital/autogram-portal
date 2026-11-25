require "test_helper"

class NotificationMailerTest < ActionMailer::TestCase
  include Rails.application.routes.url_helpers

  setup { default_url_options[:host] = "example.com" }

  test "signature requested escapes bundle note HTML" do
    bundle = create_bundle_with_note("<b>Phish</b>\nline2")

    mail = NotificationMailer.with(user: users(:two)).signature_requested(bundle)
    body = mail.html_part ? mail.html_part.body.encoded : mail.body.encoded

    assert_includes body, "&lt;b&gt;Phish&lt;/b&gt;"
    assert_includes body, "line2"
    assert_not_includes body, "<b>Phish</b>"
  end

  test "signature requested names the bundle in the heading" do
    bundle = create_bundle_with_note("Prosím o podpis do piatka.")
    bundle.update!(name: "Zmluva o dielo – kancelária")

    mail = NotificationMailer.with(user: users(:two)).signature_requested(bundle)

    assert_equal I18n.t("notification_mailer.signature_requested.subject"), mail.subject
    assert_includes mail.html_part.body.decoded, "Zmluva o dielo – kancelária</h1>"
    assert_includes mail.text_part.body.decoded, "Zmluva o dielo – kancelária"
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

  test "paper signature submitted asks the organization to review the scan" do
    paper = paper_signature_for(create_bundle_with_note("x"), status: :submitted)
    user = users(:one)

    mail = NotificationMailer.with(user: user).paper_signature_submitted(paper)

    assert_equal [ user.email ], mail.to
    assert_equal I18n.t("notification_mailer.paper_signature_submitted.subject"), mail.subject
    [ mail.html_part.body.decoded, mail.text_part.body.decoded ].each do |body|
      assert_includes body, "signer@example.com nahral(a) sken dokumentu"
      assert_includes body, bundle_paper_signature_url(paper.signer_contract.contract.bundle, paper)
    end
    assert_includes mail.html_part.body.decoded, I18n.t("notification_mailer.paper_signature_submitted.review")
  end

  test "paper signature approved tells the signer" do
    paper = paper_signature_for(create_bundle_with_note("x"), status: :approved)

    mail = NotificationMailer.with(recipient: paper.recipient).paper_signature_approved(paper)

    assert_equal [ "signer@example.com" ], mail.to
    assert_equal I18n.t("notification_mailer.paper_signature_approved.subject"), mail.subject
    assert_includes mail.html_part.body.decoded, "schválil(a)"
    assert_includes mail.text_part.body.decoded, "schválil(a)"
  end

  test "paper signature returned gives the reason and a link to sign again" do
    paper = paper_signature_for(create_bundle_with_note("x"), status: :returned, return_reason: "Chýba <b>podpis</b>")
    bundle = paper.signer_contract.contract.bundle

    mail = NotificationMailer.with(recipient: paper.recipient).paper_signature_returned(paper)

    assert_equal I18n.t("notification_mailer.paper_signature_returned.subject"), mail.subject
    assert_includes mail.html_part.body.decoded, "Chýba &lt;b&gt;podpis&lt;/b&gt;"
    assert_includes mail.text_part.body.decoded, "Chýba <b>podpis</b>"
    assert_includes mail.html_part.body.decoded, sign_bundle_url(bundle, recipient: paper.recipient)
  end

  test "paper signature mails are in English for an English recipient" do
    paper = paper_signature_for(create_bundle_with_note("x"), status: :returned, return_reason: "Missing", locale: "en")

    mail = NotificationMailer.with(recipient: paper.recipient).paper_signature_returned(paper)

    assert_equal I18n.t("notification_mailer.paper_signature_returned.subject", locale: :en), mail.subject
    assert_not_equal I18n.t("notification_mailer.paper_signature_returned.subject", locale: :sk), mail.subject
  end

  private

  def paper_signature_for(bundle, status:, return_reason: nil, locale: "sk")
    recipient = bundle.recipients.create!(email: "signer@example.com", locale: locale)
    paper = PaperSignature.open_for!(recipient.signer_contracts.sole)
    paper.update!(status: status, return_reason: return_reason)
    paper
  end

  def create_bundle_with_note(note)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "mail-test.pdf",
      content_type: "application/pdf"
    )

    contract = Contract.new(
      tenant: users(:one).tenants.sole,
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )
    contract.save!

    bundle = Bundle.new(
      tenant: tenants(:one),
      uuid: SecureRandom.uuid,
      note: note,
      contracts: [ contract ]
    )
    bundle.save!

    bundle
  end
end
