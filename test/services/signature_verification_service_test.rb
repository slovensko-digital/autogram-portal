require "test_helper"

class SignatureVerificationServiceTest < ActiveSupport::TestCase
  class FakeSmsProvider
    attr_reader :last_code, :deliveries

    def initialize
      @deliveries = []
    end

    def deliver_code(phone_number:, code:, context: {})
      @last_code = code
      @deliveries << { phone_number: phone_number, code: code, context: context }
      "req-#{deliveries.length}"
    end
  end

  test "request_code and verify_code persist verification and evidence state" do
    session = create_ades_session
    sms_provider = FakeSmsProvider.new
    service = SignatureVerificationService.new(sms_provider: sms_provider, clock: -> { Time.zone.parse("2026-07-01 12:00:00") })

    verification = service.request_code!(session: session, ip_address: "127.0.0.1", user_agent: "RSpec")

    assert verification.sent?
    assert_equal 1, sms_provider.deliveries.size
    assert_equal "+421901234567", sms_provider.deliveries.first[:phone_number]
    assert_equal "requested", session.signature_evidence_record.reload.state
    assert_equal 1, session.signature_evidence_record.canonical_payload.fetch("events").size

    verified = service.verify_code!(session: session, code: "123456", ip_address: "127.0.0.1", user_agent: "RSpec")

    assert verified.verified?
    assert_equal "verified", session.signature_evidence_record.reload.state
    assert_equal 2, session.signature_evidence_record.canonical_payload.fetch("events").size
  end

  test "verify_code accepts arbitrary submitted code for placeholder flow" do
    session = create_ades_session
    service = SignatureVerificationService.new(sms_provider: FakeSmsProvider.new)
    service.request_code!(session: session, ip_address: "127.0.0.1", user_agent: "RSpec")

    verification = service.verify_code!(session: session, code: "000000", ip_address: "127.0.0.1", user_agent: "RSpec")

    assert verification.verified?
    assert_equal 0, session.signature_verification.reload.attempts_count
  end

  private

  def create_ades_session
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "ades-session.pdf",
      content_type: "application/pdf"
    )

    contract = Contract.create!(
      allowed_methods: [ "ades" ],
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )
    bundle = Bundle.create!(author: users(:one), contracts: [ contract ])
    recipient = bundle.recipients.create!(
      email: "recipient-#{SecureRandom.hex(4)}@example.com",
      locale: "en",
      mobile_phone: "+421901234567"
    )
    signer_contract = recipient.recipient_signer.signer_contracts.find_by!(contract: contract)

    signer_contract.sessions.create!(
      type: "AdesEvidenceSession",
      signing_started_at: Time.current,
      options: { "verification_channel" => "sms" }
    )
  end
end
