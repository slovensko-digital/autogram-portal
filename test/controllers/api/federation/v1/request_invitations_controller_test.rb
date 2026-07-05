require "test_helper"
require "jwt"
require "openssl"

class Api::Federation::V1::RequestInvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    users(:two).update_column(:email, "recipient@partner.example")

    @portal_key = OpenSSL::PKey::RSA.generate(2048)
    @portal_instance = PortalInstance.create!(
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://partner.example",
      public_key_pem: @portal_key.public_key.to_pem,
      allowed_email_domains: [ "partner.example" ]
    )
  end

  test "create stores invitation for authorized portal" do
    params = invitation_params

    post "/api/federation/v1/request_invitations",
         params: { invitation: params },
         headers: portal_headers(scope: "federation.request.invitation.send")

    assert_response :created

    invitation = FederationRequestInvitation.find_by!(
      portal_instance: @portal_instance,
      origin_recipient_uuid: params[:recipientId]
    )

    assert_equal params[:bundleId], invitation.origin_bundle_uuid
    assert_equal params[:recipientEmail], invitation.recipient_email
    assert_equal users(:two), invitation.recipient_user
    assert_equal "pending", invitation.status
    assert_equal params[:openUrl], invitation.payload.fetch("openUrl")
  end

  test "create is idempotent for the same portal recipient pair" do
      params = invitation_params

      post "/api/federation/v1/request_invitations",
        params: { invitation: params },
         headers: portal_headers(scope: "federation.request.invitation.send")

      updated_params = params.merge(note: "Updated note")

    post "/api/federation/v1/request_invitations",
         params: { invitation: updated_params },
         headers: portal_headers(scope: "federation.request.invitation.send")

    assert_response :created
    assert_equal 1, FederationRequestInvitation.count
    assert_equal "Updated note", FederationRequestInvitation.first.payload.fetch("note")
  end

  test "withdraw marks invitation as withdrawn" do
    invitation = FederationRequestInvitation.create!(
      portal_instance: @portal_instance,
      origin_recipient_uuid: invitation_params[:recipientId],
      origin_bundle_uuid: invitation_params[:bundleId],
      recipient_email: invitation_params[:recipientEmail],
      payload: invitation_params
    )

    post "/api/federation/v1/request_invitations/#{invitation.origin_recipient_uuid}/withdraw",
         headers: portal_headers(scope: "federation.request.invitation.withdraw")

    assert_response :success

    invitation.reload
    assert_equal "withdrawn", invitation.status
    assert_not_nil invitation.withdrawn_at
  end

  test "withdraw can mark invitation as signed" do
    invitation = FederationRequestInvitation.create!(
      portal_instance: @portal_instance,
      origin_recipient_uuid: invitation_params[:recipientId],
      origin_bundle_uuid: invitation_params[:bundleId],
      recipient_email: invitation_params[:recipientEmail],
      payload: invitation_params
    )

    post "/api/federation/v1/request_invitations/#{invitation.origin_recipient_uuid}/withdraw",
         params: { status: "signed" },
         headers: portal_headers(scope: "federation.request.invitation.withdraw")

    assert_response :success

    invitation.reload
    assert_equal "signed", invitation.status
    assert_not_nil invitation.withdrawn_at
  end

  private

  def invitation_params
    {
      recipientId: SecureRandom.uuid,
      bundleId: SecureRandom.uuid,
      recipientEmail: "recipient@partner.example",
      authorName: "Sender User",
      note: "Please sign this bundle",
      openUrl: "https://origin.example/bundles/123/sign?recipient=abc",
      status: "awaiting",
      originPortal: {
        issuer: "https://origin.example",
        name: "Origin portal"
      },
      contracts: [
        {
          id: SecureRandom.uuid,
          displayName: "Contract A"
        }
      ]
    }
  end

  def portal_headers(scope:, issuer: @portal_instance.issuer, key: @portal_key)
    token = JWT.encode(
      {
        iss: issuer,
        aud: "http://www.example.com",
        exp: 3.minutes.from_now.to_i,
        jti: SecureRandom.hex(16),
        scope: scope
      },
      key,
      "RS256"
    )

    {
      "Authorization" => "Bearer #{token}",
      "Accept" => "application/json"
    }
  end
end
