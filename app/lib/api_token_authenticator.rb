class ApiTokenAuthenticator
  MAX_EXP_IN = 15.minutes
  JTI_PATTERN = /\A[0-9a-z\-_]{32,256}\z/i
  SUPPORTED_ALGORITHMS = [ "RS256", "ES256" ]

  def initialize(public_key_reader:, return_handler:, first_use_recorder:)
    @public_key_reader = public_key_reader
    @return_handler = return_handler
    @first_use_recorder = first_use_recorder
  end

  def verify_token(token)
    options = {
      algorithm: SUPPORTED_ALGORITHMS,
      verify_jti: ->(jti) { jti =~ JTI_PATTERN }
    }

    key_finder = ->(_, payload) do
      @public_key_reader.call(payload["sub"])
    rescue
      raise JWT::InvalidSubError
    end

    payload, _ = JWT.decode(token, nil, true, options, &key_finder)
    sub, exp, jti = payload["sub"], payload["exp"], payload["jti"]

    raise JWT::ExpiredSignature unless exp.is_a?(Integer)
    raise JWT::InvalidPayload if exp > (Time.now + MAX_EXP_IN).to_i

    result = @return_handler.call(sub)

    # Only verified tokens are recorded, so nobody without the key can use up a jti.
    raise JWT::InvalidJtiError, "Token has already been used" unless @first_use_recorder.call(result, jti, Time.at(exp))

    result
  end
end
