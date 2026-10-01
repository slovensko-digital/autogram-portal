module ApiEnvironment
  def self.token_authenticator
    @token_authenticator ||= use_dummy_authenticator? ? DummyAuthenticator.new : ApiTokenAuthenticator.new(
      public_key_reader: API_TENANT_PUBLIC_KEY_READER,
      return_handler: API_TENANT_BY_IDENTITY_FINDER,
    )
  end

  API_TENANT_PUBLIC_KEY_READER = ->(sub) { OpenSSL::PKey.read(API_TENANT_BY_IDENTITY_FINDER.call(sub).api_token_public_key) }
  API_TENANT_BY_IDENTITY_FINDER = ->(sub) do
    raise unless sub&.to_i

    tenant = Tenant.find(sub&.to_i)

    raise unless tenant&.api_enabled?

    tenant
  end

  def self.use_dummy_authenticator?
    Rails.env == "development" && ENV["API_SKIP_AUTH"] == "true"
  end

  class DummyAuthenticator
    def verify_token(_token)
      Tenant.second || raise("No tenants in DB")
    end
  end
end
