class Federation::MetadataController < ActionController::API
  def show
    render json: {
      issuer: FederationConfiguration.issuer(request: request),
      baseUrl: FederationConfiguration.base_url(request: request),
      portalName: FederationConfiguration.portal_name,
      federationApiBase: FederationConfiguration.federation_api_base(request: request),
      publicKeyPem: FederationConfiguration.public_key_pem,
      capabilities: FederationConfiguration.capabilities,
      emailDomains: FederationConfiguration.email_domains
    }
  end
end
