class PortalAssertionAuthenticator
  Assertion = Struct.new(:portal_instance, :payload, keyword_init: true)

  MAX_EXP_IN = 5.minutes
  JTI_PATTERN = /\A[0-9a-z\-_]{16,256}\z/i
  SUPPORTED_ALGORITHMS = [ "RS256", "ES256" ].freeze

  def verify_token(token, audience:, required_scope:)
    raise JWT::DecodeError, "Missing federation token" if token.blank?

    portal_instance = nil
    payload, = JWT.decode(token, nil, true, decode_options(audience: audience)) do |_header, decoded_payload|
      portal_instance = PortalInstance.trusted.find_by!(issuer: decoded_payload.fetch("iss"))
      OpenSSL::PKey.read(portal_instance.public_key_pem)
    end

    exp = payload["exp"]
    raise JWT::ExpiredSignature unless exp.is_a?(Integer)
    raise JWT::InvalidPayload, "exp is too far in the future" if exp > MAX_EXP_IN.from_now.to_i

    scope_values = payload["scope"].to_s.split
    raise JWT::InvalidPayload, "Missing required scope" unless scope_values.include?(required_scope)

    Assertion.new(portal_instance: portal_instance, payload: payload)
  end

  private

  def decode_options(audience:)
    {
      algorithm: SUPPORTED_ALGORITHMS,
      verify_aud: true,
      aud: audience,
      verify_jti: ->(jti) { jti =~ JTI_PATTERN }
    }
  end
end
