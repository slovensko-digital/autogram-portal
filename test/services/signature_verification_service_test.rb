require "test_helper"

class SignatureVerificationServiceTest < ActiveSupport::TestCase
  class FakeSmsProvider
    attr_reader :last_code, :deliveries

    def initialize
      @deliveries = []
    end

    def deliver_code(phone_number:, code:, locale: I18n.default_locale, context: {})
      @last_code = code
      @deliveries << { phone_number: phone_number, code: code, locale: locale, context: context }
      "req-#{deliveries.length}"
    end
  end

  class FakeEmailProvider
    attr_reader :last_code, :deliveries

    def initialize
      @deliveries = []
    end

    def deliver_code(email:, code:, locale: I18n.default_locale, context: {})
      @last_code = code
      @deliveries << { email: email, code: code, locale: locale, context: context }
      "email-#{deliveries.length}"
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

    verified = service.verify_code!(session: session, code: sms_provider.last_code, ip_address: "127.0.0.1", user_agent: "RSpec")

    assert verified.verified?
    assert_equal "verified", session.signature_evidence_record.reload.state
    assert_equal 2, session.signature_evidence_record.canonical_payload.fetch("events").size
  end

  test "verify_code rejects invalid submitted code" do
    session = create_ades_session
    sms_provider = FakeSmsProvider.new
    service = SignatureVerificationService.new(sms_provider: sms_provider)
    service.request_code!(session: session, ip_address: "127.0.0.1", user_agent: "RSpec")

    error = assert_raises(SignatureVerificationService::VerificationCodeMismatchError) do
      service.verify_code!(session: session, code: "000000", ip_address: "127.0.0.1", user_agent: "RSpec")
    end

    assert_equal I18n.t("contracts.sessions.ades_evidence.errors.invalid_code"), error.message
    assert session.signature_verification.reload.sent?
    assert_equal 1, session.signature_verification.attempts_count
    assert_equal "sms_verification_failed", session.signature_evidence_record.reload.canonical_payload.fetch("events").last.fetch("type")
  end

  test "request_code falls back to email when sms provider is unavailable" do
    session = create_ades_session
    email_provider = FakeEmailProvider.new
    service = SignatureVerificationService.new(sms_provider: nil, email_provider: email_provider)

    verification = service.request_code!(session: session, ip_address: "127.0.0.1", user_agent: "RSpec")

    assert verification.sent?
    assert_equal "email", verification.channel
    assert_equal 1, email_provider.deliveries.size
    assert_equal session.recipient.email, email_provider.deliveries.first[:email]
    assert_equal "email", session.reload.verification_channel
    assert_equal "email_requested", session.signature_evidence_record.reload.canonical_payload.fetch("events").last.fetch("type")
  end

  test "verify_code raises too many attempts after repeated mismatches" do
    session = create_ades_session
    service = SignatureVerificationService.new(sms_provider: FakeSmsProvider.new)
    service.request_code!(session: session, ip_address: "127.0.0.1", user_agent: "RSpec")

    (SignatureVerification::MAX_ATTEMPTS - 1).times do
      assert_raises(SignatureVerificationService::VerificationCodeMismatchError) do
        service.verify_code!(session: session, code: "000000", ip_address: "127.0.0.1", user_agent: "RSpec")
      end
    end

    error = assert_raises(SignatureVerificationService::VerificationAttemptsExceededError) do
      service.verify_code!(session: session, code: "000000", ip_address: "127.0.0.1", user_agent: "RSpec")
    end

    assert_equal I18n.t("contracts.sessions.ades_evidence.errors.too_many_attempts"), error.message
    assert session.signature_verification.reload.failed?
    assert_equal SignatureVerification::MAX_ATTEMPTS, session.signature_verification.attempts_count
    assert_equal "sms_failed", session.signature_evidence_record.reload.canonical_payload.fetch("events").last.fetch("type")
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
