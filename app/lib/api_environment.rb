module ApiEnvironment
  def self.token_authenticator
    @token_authenticator ||= use_dummy_authenticator? ? DummyAuthenticator.new : ApiTokenAuthenticator.new(
      public_key_reader: API_USER_PUBLIC_KEY_READER,
      return_handler: API_USER_BY_IDENTITY_FINDER,
    )
  end

  API_USER_PUBLIC_KEY_READER = ->(sub) { OpenSSL::PKey::RSA.new(API_USER_BY_IDENTITY_FINDER.call(sub).api_token_public_key) }
  API_USER_BY_IDENTITY_FINDER = ->(sub) do
    raise unless sub&.to_i

    user = User.find(sub&.to_i)

    raise unless user

    user
  end

  def self.use_dummy_authenticator?
    Rails.env == "development" && ENV["API_SKIP_AUTH"] == "true"
  end

  class DummyAuthenticator
    def verify_token(_token)
      User.first || raise("No users in DB")
    end
  end
end
