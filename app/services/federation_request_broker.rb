class FederationRequestBroker
  RemotePortal = Struct.new(:name, :base_url, :issuer, :capabilities, keyword_init: true)
  Preview = Struct.new(:portal_instance, :request, keyword_init: true)
  RequestContext = Struct.new(:portal_instance, :bundle_uuid, :recipient_uuid, keyword_init: true)

  class Error < StandardError; end
  class InvalidRequestUrlError < Error; end
  class UntrustedPortalError < Error; end
  class UnsupportedPortalError < Error; end

  def initialize(client: FederationPortalClient.new)
    @client = client
  end

  def preview(url:)
    context = resolve_context(url)
    request = @client.fetch_request_preview(
      portal_instance: context.portal_instance,
      recipient_uuid: context.recipient_uuid,
      bundle_uuid: context.bundle_uuid
    )

    context.portal_instance.name ||= request.dig("originPortal", "name") || URI.parse(context.portal_instance.base_url).host

    Preview.new(
      portal_instance: context.portal_instance,
      request: request
    )
  end

  def claim(url:, claimant:)
    context = resolve_context(url)

    @client.claim_request(
      portal_instance: context.portal_instance,
      recipient_uuid: context.recipient_uuid,
      bundle_uuid: context.bundle_uuid,
      claimant: claimant
    )
  end

  private

  def resolve_context(url)
    uri = URI.parse(url.to_s)
    raise InvalidRequestUrlError, I18n.t("federation.requests.errors.invalid_url") unless uri.is_a?(URI::HTTP) && uri.host.present?

    bundle_uuid = uri.path.match(%r{\A/bundles/([^/]+)/sign\z})&.captures&.first
    recipient_uuid = Rack::Utils.parse_nested_query(uri.query).presence&.fetch("recipient", nil)

    raise InvalidRequestUrlError, I18n.t("federation.requests.errors.invalid_url") if bundle_uuid.blank? || recipient_uuid.blank?

    portal_instance = discover_origin_portal(uri)

    RequestContext.new(portal_instance: portal_instance, bundle_uuid: bundle_uuid, recipient_uuid: recipient_uuid)
  rescue URI::InvalidURIError
    raise InvalidRequestUrlError, I18n.t("federation.requests.errors.invalid_url")
  end

  def discover_origin_portal(uri)
    base_url = origin_base_url(uri)
    validate_origin_base_url!(base_url)

    metadata = @client.fetch_metadata(base_url: base_url)
    capabilities = metadata.fetch("capabilities", {})
    raise UnsupportedPortalError, I18n.t("federation.requests.errors.unsupported_portal") unless capabilities["requestPreview"] && capabilities["requestClaim"]

    issuer = metadata["issuer"].presence
    raise UnsupportedPortalError, I18n.t("federation.requests.errors.unsupported_portal") if issuer.blank?

    RemotePortal.new(
      name: metadata["portalName"].presence,
      base_url: metadata["baseUrl"].presence || base_url,
      issuer: issuer,
      capabilities: capabilities
    )
  end

  def origin_base_url(uri)
    port_segment = if uri.port.present? && uri.port != uri.default_port
      ":#{uri.port}"
    else
      ""
    end

    "#{uri.scheme}://#{uri.host}#{port_segment}"
  end

  def validate_origin_base_url!(base_url)
    candidate = PortalInstance.new(
      name: "Discovered portal",
      base_url: base_url,
      issuer: "temp-#{SecureRandom.hex(8)}",
      public_key_pem: "placeholder"
    )

    candidate.valid?
    raise InvalidRequestUrlError, candidate.errors[:base_url].first if candidate.errors[:base_url].present?
  end
end
