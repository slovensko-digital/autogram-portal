class SignatureVerificationService
  CODE_TTL = 10.minutes

  class Error < StandardError; end
  class MissingRecipientPhoneError < Error; end
  class VerificationNotRequestedError < Error; end
  class VerificationCodeMismatchError < Error; end
  class VerificationExpiredError < Error; end
  class VerificationAlreadyCompletedError < Error; end
  class VerificationAttemptsExceededError < Error; end

  def initialize(sms_provider: AutogramEnvironment.sms_provider, clock: -> { Time.current })
    @sms_provider = sms_provider
    @clock = clock
  end

  def request_code!(session:, ip_address:, user_agent:)
    raise MissingRecipientPhoneError, I18n.t("contracts.sessions.ades_evidence.missing_phone") if session.recipient_mobile_phone.blank?
    raise VerificationAlreadyCompletedError, I18n.t("contracts.sessions.ades_evidence.errors.already_verified") if session.verification_verified?

    code = generate_code
    now = @clock.call
    provider_request_id = @sms_provider.deliver_code(
      phone_number: session.recipient_mobile_phone,
      code: code,
      context: {
        contract_id: session.contract.uuid,
        session_id: session.id,
        recipient_id: session.recipient&.uuid
      }
    )

    verification = session.signature_verification || session.build_signature_verification(channel: "sms")
    verification.assign_attributes(
      channel: "sms",
      state: "sent",
      destination: session.recipient_mobile_phone,
      destination_digest: digest_value(session.recipient_mobile_phone),
      code_digest: digest_value(code),
      provider_request_id: provider_request_id,
      sent_at: now,
      expires_at: now + CODE_TTL,
      attempts_count: 0,
      last_request_ip: ip_address,
      last_user_agent: user_agent,
      verified_at: nil
    )
    verification.save!

    session.update!(error_message: nil)

    evidence_record = session.ensure_signature_evidence_record!
    evidence_record.update!(state: "requested")
    evidence_record.append_event!(
      type: "sms_requested",
      details: {
        channel: "sms",
        destination: session.recipient_masked_mobile_phone,
        provider_request_id: provider_request_id,
        ip_address: ip_address,
        user_agent: user_agent
      },
      occurred_at: now
    )

    verification
  end

  def verify_code!(session:, code:, ip_address:, user_agent:)
    verification = session.signature_verification
    raise VerificationNotRequestedError, I18n.t("contracts.sessions.ades_evidence.errors.not_requested") if verification.blank?
    raise VerificationAlreadyCompletedError, I18n.t("contracts.sessions.ades_evidence.errors.already_verified") if verification.verified?

    now = @clock.call
    evidence_record = session.ensure_signature_evidence_record!

    if verification.expired_now?(now)
      verification.update!(state: "expired")
      evidence_record.append_event!(
        type: "sms_expired",
        details: { ip_address: ip_address, user_agent: user_agent },
        occurred_at: now
      )
      raise VerificationExpiredError, I18n.t("contracts.sessions.ades_evidence.errors.expired")
    end

    verification.update!(
      state: "verified",
      verified_at: now,
      last_request_ip: ip_address,
      last_user_agent: user_agent
    )
    session.update!(error_message: nil)
    evidence_record.update!(state: "verified")
    evidence_record.append_event!(
      type: "sms_verified",
      details: {
        ip_address: ip_address,
        user_agent: user_agent,
        provider_request_id: verification.provider_request_id,
        placeholder_verification: true
      },
      occurred_at: now
    )

    verification
  end

  private

  def generate_code
    format("%06d", SecureRandom.random_number(1_000_000))
  end

  def digest_value(value)
    Digest::SHA256.hexdigest(value.to_s)
  end
end
