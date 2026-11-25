require "test_helper"

class PaperSignatureAccessTokenTest < ActiveSupport::TestCase
  setup do
    tenant = Tenant.create!(name: "Firma ABC", plan: :pro)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(Prawn::Document.new.render), filename: "zmluva.pdf", content_type: "application/pdf")
    bundle = Bundle.create!(tenant: tenant, contracts: [ Contract.create!(documents_attributes: [ { blob: blob } ], signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }) ])
    recipient = bundle.recipients.create!(email: "external@example.com", locale: "sk")
    @paper = PaperSignature.open_for!(recipient.signer_contracts.sole)
  end

  test "a token opens its paper signature for an hour" do
    token = PaperSignatureAccessToken.generate(@paper)

    assert_equal @paper, PaperSignatureAccessToken.verify(token)
    travel 59.minutes
    assert_equal @paper, PaperSignatureAccessToken.verify(token)
    travel 2.minutes
    assert_nil PaperSignatureAccessToken.verify(token)
  end

  test "an expired token opens nothing" do
    assert_nil PaperSignatureAccessToken.verify(PaperSignatureAccessToken.generate(@paper, expires_at: 1.minute.ago))
  end

  test "the token carries only the paper signature and its expiry" do
    expires_at = 10.minutes.from_now
    token = PaperSignatureAccessToken.generate(@paper, expires_at: expires_at)

    payload = Rails.application.message_verifier("paper-signature-access").verify(token)
    assert_equal({ "paper_signature_uuid" => @paper.uuid, "exp" => expires_at.to_i }, payload)
  end

  test "a tampered, foreign or missing token opens nothing" do
    token = PaperSignatureAccessToken.generate(@paper)
    session_token = Rails.application.message_verifier(SessionAccessToken::PURPOSE).generate({ paper_signature_uuid: @paper.uuid, exp: 1.hour.from_now.to_i })

    [ "#{token}x", token.reverse, session_token, "garbage", "", nil, { "paper_signature_uuid" => @paper.uuid } ].each do |forged|
      assert_nil PaperSignatureAccessToken.verify(forged), "#{forged.inspect} opens the paper signature"
    end
  end

  test "a token of a deleted paper signature opens nothing" do
    token = PaperSignatureAccessToken.generate(@paper)
    @paper.destroy!

    assert_nil PaperSignatureAccessToken.verify(token)
  end
end
