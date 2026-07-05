class FederationConfiguration
  class << self
    def static_base_url
      ENV["FEDERATION_BASE_URL"].presence || ENV["FEDERATION_ISSUER"].presence || "http://www.example.com"
    end

    def static_issuer
      ENV["FEDERATION_ISSUER"].presence || static_base_url
    end

    def issuer(request:)
      ENV["FEDERATION_ISSUER"].presence || request.base_url
    end

    def base_url(request:)
      ENV["FEDERATION_BASE_URL"].presence || request.base_url
    end

    def federation_api_base(request:)
      "#{base_url(request: request)}/api/federation/v1"
    end

    def public_key_pem
      ENV["FEDERATION_PUBLIC_KEY_PEM"].presence
    end

    def portal_name
      ENV["FEDERATION_PORTAL_NAME"].presence || "Autogram Portal"
    end

    def capabilities
      {
        requestPreview: true,
        requestClaim: true,
        requestInvitationSend: true,
        requestInvitationWithdraw: true,
        specVersion: "1"
      }
    end

    def email_domains
      ENV.fetch("FEDERATION_EMAIL_DOMAINS", "")
        .split(",")
        .filter_map { |domain| domain.strip.downcase.presence }
    end
  end
end
