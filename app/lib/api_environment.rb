module ApiEnvironment
  def self.token_authenticator
    @token_authenticator ||= use_dummy_authenticator? ? DummyAuthenticator.new : ApiTokenAuthenticator.new(
      public_key_reader: API_TOKEN_PUBLIC_KEY_READER,
      return_handler: TENANT_BY_API_TOKEN_IDENTIFIER,
    )
  end

  TENANT_BY_API_TOKEN_IDENTIFIER = ->(sub) do
    tenant = Tenant.find_by!(api_token_identifier: sub.to_s)
    raise JWT::InvalidSubError unless tenant.api_enabled? && tenant.api_token_public_key.present?

    tenant
  end
  API_TOKEN_PUBLIC_KEY_READER = ->(sub) { OpenSSL::PKey.read(TENANT_BY_API_TOKEN_IDENTIFIER.call(sub).api_token_public_key) }

  def self.use_dummy_authenticator?
    Rails.env == "development" && ENV["API_SKIP_AUTH"] == "true"
  end

  class DummyAuthenticator
    def verify_token(_token)
      Tenant.with_feature(:api)
            .where.not(api_token_public_key: [ nil, "" ])
            .first || raise(JWT::InvalidSubError)
    end
  end
end
