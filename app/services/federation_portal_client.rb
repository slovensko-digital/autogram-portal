class FederationPortalClient
  def initialize(provider: Faraday)
    @provider = provider
  end

  def fetch_metadata(base_url:)
    response = connection(base_url).get(metadata_path) do |request|
      request.headers["Accept"] = "application/json"
    end

    parse_response(response)
  end

  def fetch_request_preview(portal_instance:, recipient_uuid:, bundle_uuid:)
    response = connection(portal_instance.base_url).get(preview_path(recipient_uuid), { bundleId: bundle_uuid }) do |request|
      request.headers["Authorization"] = bearer_token(portal_instance: portal_instance, scope: "federation.request.read")
      request.headers["Accept"] = "application/json"
    end

    parse_response(response).fetch("request")
  end

  def claim_request(portal_instance:, recipient_uuid:, bundle_uuid:, claimant:)
    response = connection(portal_instance.base_url).post(claim_path(recipient_uuid)) do |request|
      request.headers["Authorization"] = bearer_token(portal_instance: portal_instance, scope: "federation.request.claim")
      request.headers["Accept"] = "application/json"
      request.headers["Content-Type"] = "application/json"
      request.body = {
        bundleId: bundle_uuid,
        claimant: {
          email: claimant.fetch(:email),
          displayName: claimant.fetch(:display_name),
          externalUserId: claimant.fetch(:external_user_id)
        }
      }
    end

    parse_response(response).fetch("claim").fetch("signUrl")
  end

  def send_request_invitation(portal_instance:, invitation:)
    response = connection(portal_instance.base_url).post(request_invitations_path) do |request|
      request.headers["Authorization"] = bearer_token(portal_instance: portal_instance, scope: "federation.request.invitation.send")
      request.headers["Accept"] = "application/json"
      request.headers["Content-Type"] = "application/json"
      request.body = { invitation: invitation }
    end

    parse_response(response).fetch("invitation")
  end

  def withdraw_request_invitation(portal_instance:, recipient_uuid:)
    response = connection(portal_instance.base_url).post(withdraw_request_invitation_path(recipient_uuid)) do |request|
      request.headers["Authorization"] = bearer_token(portal_instance: portal_instance, scope: "federation.request.invitation.withdraw")
      request.headers["Accept"] = "application/json"
      request.headers["Content-Type"] = "application/json"
    end

    parse_response(response).fetch("invitation")
  end

  private

  def connection(base_url)
    @provider.new(url: base_url) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 15
    end
  end

  def bearer_token(portal_instance:, scope:)
    "Bearer #{FederationAssertionToken.issue!(scope: scope, audience: portal_instance.issuer)}"
  end

  def metadata_path
    "/.well-known/autogram-portal.json"
  end

  def preview_path(recipient_uuid)
    "/api/federation/v1/requests/#{recipient_uuid}"
  end

  def claim_path(recipient_uuid)
    "/api/federation/v1/requests/#{recipient_uuid}/claim"
  end

  def request_invitations_path
    "/api/federation/v1/request_invitations"
  end

  def withdraw_request_invitation_path(recipient_uuid)
    "/api/federation/v1/request_invitations/#{recipient_uuid}/withdraw"
  end

  def parse_response(response)
    return response.body if response.success? && response.body.is_a?(Hash)

    message = response.body.is_a?(Hash) ? response.body["message"] : response.body.to_s
    raise FederationRequestBroker::Error, message.presence || I18n.t("federation.requests.errors.remote_request_failed")
  end
end
