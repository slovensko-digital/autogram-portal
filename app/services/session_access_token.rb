class SessionAccessToken
  PURPOSE = "contract-session-access".freeze
  DEFAULT_TTL = 30.minutes

  class << self
    def generate(contract:, session:, expires_at: DEFAULT_TTL.from_now)
      verifier.generate(
        {
          contract_uuid: contract.uuid,
          session_id: session.id,
          exp: expires_at.to_i
        }
      )
    end

    def valid?(token:, contract:, session:)
      payload = verifier.verify(token).with_indifferent_access
      recipient = session.recipient

      return false if recipient&.withdrawn?

      payload[:contract_uuid] == contract.uuid &&
        payload[:session_id].to_i == session.id &&
        payload[:exp].to_i >= Time.current.to_i
    rescue ActiveSupport::MessageVerifier::InvalidSignature, TypeError
      false
    end

    private

    def verifier
      Rails.application.message_verifier(PURPOSE)
    end
  end
end
