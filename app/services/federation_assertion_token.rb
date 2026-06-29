class FederationAssertionToken
  DEFAULT_TTL = 5.minutes

  class << self
    def issue!(scope:, audience:, expires_at: DEFAULT_TTL.from_now)
      JWT.encode(
        {
          iss: FederationConfiguration.static_issuer,
          aud: audience,
          exp: expires_at.to_i,
          jti: SecureRandom.hex(16),
          scope: scope
        },
        signing_key,
        "RS256"
      )
    end

    private

    def signing_key
      pem = ENV["FEDERATION_PRIVATE_KEY_PEM"].presence
      raise FederationRequestBroker::Error, I18n.t("federation.requests.errors.private_key_missing") if pem.blank?

      OpenSSL::PKey.read(pem)
    end
  end
end
