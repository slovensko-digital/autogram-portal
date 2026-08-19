require "jwt"
require "openssl"

module ApiTestHelper
  def enable_api_for!(tenant)
    tenant.update_column(:features, (tenant.features + [ "api" ]).uniq)
  end

  # Generates a key, sets it as the tenant's api_token_public_key, and returns the private key.
  def attach_api_key!(tenant:, algorithm: "RS256")
    key = case algorithm
    when "ES256"
      OpenSSL::PKey::EC.generate("prime256v1")
    when "RS256"
      OpenSSL::PKey::RSA.generate(2048)
    else
      raise ArgumentError, "Unsupported algorithm: #{algorithm}"
    end

    tenant.update_column(:api_token_public_key, key.public_to_pem)
    key
  end

  def bearer_headers_for(tenant, key, algorithm: "RS256")
    token = JWT.encode(
      {
        sub: tenant.api_token_identifier,
        exp: 10.minutes.from_now.to_i,
        jti: SecureRandom.hex(16)
      },
      key,
      algorithm
    )

    {
      "Authorization" => "Bearer #{token}",
      "Accept" => "application/json"
    }
  end
end
