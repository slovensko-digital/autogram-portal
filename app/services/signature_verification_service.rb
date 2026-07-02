class SignatureVerificationService
  CODE_TTL = 10.minutes

  class Error < StandardError; end
  class MissingRecipientContactError < Error; end
  class VerificationNotRequestedError < Error; end
  class VerificationCodeMismatchError < Error; end
  class VerificationExpiredError < Error; end
  class VerificationAlreadyCompletedError < Error; end
  class VerificationAttemptsExceededError < Error; end

  def initialize(sms_provider: AutogramEnvironment.sms_provider, email_provider: AutogramEnvironment.email_otp_provider, clock: -> { Time.current })
    @sms_provider = sms_provider
    @email_provider = email_provider
    @clock = clock
  end

  def request_code!(session:, ip_address:, user_agent:)
    raise VerificationAlreadyCompletedError, I18n.t("contracts.sessions.ades_evidence.errors.already_verified") if session.verification_verified?

    channel = resolve_channel(session)
    raise MissingRecipientContactError, I18n.t("contracts.sessions.ades_evidence.missing_contact") if channel.blank?

    code = generate_code
    now = @clock.call
    context = {
      contract_id: session.contract.uuid,
      session_id: session.id,
      recipient_id: session.recipient&.uuid
    }

    destination, provider_request_id = deliver_code(session: session, channel: channel, code: code, context: context)

    verification = session.signature_verification || session.build_signature_verification(channel: channel)
    verification.assign_attributes(
      channel: channel,
      state: "sent",
      destination: destination,
      destination_digest: digest_value(destination),
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

    session.update!(error_message: nil, verification_channel: channel)

    evidence_record = session.ensure_signature_evidence_record!
    evidence_record.update!(state: "requested")
    evidence_record.append_event!(
      type: "#{channel}_requested",
      details: {
        channel: channel,
        destination: masked_destination(session, channel),
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
    raise VerificationAttemptsExceededError, I18n.t("contracts.sessions.ades_evidence.errors.too_many_attempts") if verification.failed? || verification.attempts_remaining <= 0

    now = @clock.call
    evidence_record = session.ensure_signature_evidence_record!
    submitted_code = normalize_code(code)

    if verification.expired_now?(now)
      verification.update!(state: "expired")
      evidence_record.append_event!(
        type: "#{verification.channel}_expired",
        details: { channel: verification.channel, ip_address: ip_address, user_agent: user_agent },
        occurred_at: now
      )
      raise VerificationExpiredError, I18n.t("contracts.sessions.ades_evidence.errors.expired")
    end

    unless codes_match?(submitted_code, verification.code_digest, channel: verification.channel)
      attempts_count = verification.attempts_count.to_i + 1
      failed = attempts_count >= SignatureVerification::MAX_ATTEMPTS

      verification.update!(
        state: failed ? "failed" : "sent",
        attempts_count: attempts_count,
        last_request_ip: ip_address,
        last_user_agent: user_agent
      )

      evidence_record.append_event!(
        type: failed ? "#{verification.channel}_failed" : "#{verification.channel}_verification_failed",
        details: {
          channel: verification.channel,
          attempts_count: attempts_count,
          attempts_remaining: [ SignatureVerification::MAX_ATTEMPTS - attempts_count, 0 ].max,
          ip_address: ip_address,
          user_agent: user_agent
        },
        occurred_at: now
      )

      raise(failed ? VerificationAttemptsExceededError : VerificationCodeMismatchError, I18n.t(failed ? "contracts.sessions.ades_evidence.errors.too_many_attempts" : "contracts.sessions.ades_evidence.errors.invalid_code"))
    end

    verification.update!(
      state: "verified",
      verified_at: now,
      attempts_count: 0,
      last_request_ip: ip_address,
      last_user_agent: user_agent
    )
    session.update!(error_message: nil)
    evidence_record.update!(state: "verified")
    evidence_record.append_event!(
      type: "#{verification.channel}_verified",
      details: {
        channel: verification.channel,
        ip_address: ip_address,
        user_agent: user_agent,
        provider_request_id: verification.provider_request_id
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

  def normalize_code(code)
    code.to_s.strip
  end

  def codes_match?(submitted_code, stored_digest, channel: nil)
    return false if submitted_code.blank? || stored_digest.blank?

    return true if channel == "sms" && @sms_provider.is_a?(Verification::NullSmsProvider)

    ActiveSupport::SecurityUtils.secure_compare(digest_value(submitted_code), stored_digest)
  end

  def resolve_channel(session)
    [ session.signature_verification&.channel, session.verification_channel, "sms", "email" ].compact.uniq.find do |channel|
      case channel
      when "sms"
        session.recipient_mobile_phone.present? && @sms_provider.present?
      when "email"
        session.recipient_email.present? && @email_provider.present?
      else
        false
      end
    end
  end

  def deliver_code(session:, channel:, code:, context:)
    locale = session.recipient&.locale || I18n.default_locale

    case channel
    when "sms"
      [
        session.recipient_mobile_phone,
        @sms_provider.deliver_code(
          phone_number: session.recipient_mobile_phone,
          code: code,
          locale: locale,
          context: context
        )
      ]
    when "email"
      [
        session.recipient_email,
        @email_provider.deliver_code(
          email: session.recipient_email,
          code: code,
          locale: locale,
          context: context
        )
      ]
    else
      raise MissingRecipientContactError, I18n.t("contracts.sessions.ades_evidence.missing_contact")
    end
  end

  def masked_destination(session, channel)
    channel == "email" ? session.recipient_masked_email : session.recipient_masked_mobile_phone
  end
end
