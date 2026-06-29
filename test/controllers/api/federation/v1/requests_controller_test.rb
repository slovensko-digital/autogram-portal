require "test_helper"
require "jwt"
require "openssl"

class Api::Federation::V1::RequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @portal_key = OpenSSL::PKey::RSA.generate(2048)
    @portal_instance = PortalInstance.create!(
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://partner.example",
      public_key_pem: @portal_key.public_key.to_pem,
      allowed_email_domains: [ "partner.example" ]
    )
    @recipient = create_federated_recipient(@portal_instance)
  end

  test "preview returns federated request details for authorized portal" do
    get "/api/federation/v1/requests/#{@recipient.uuid}",
        params: { bundleId: @recipient.bundle.uuid },
        headers: portal_headers(scope: "federation.request.read")

    assert_response :success
    request_payload = response.parsed_body.fetch("request")

    assert_equal @recipient.uuid, request_payload.fetch("recipientId")
    assert_equal @recipient.bundle.uuid, request_payload.fetch("bundleId")
    assert_equal @recipient.email, request_payload.fetch("recipientEmail")
    assert_equal @portal_instance.uuid, request_payload.fetch("recipientPortalId")
  end

  test "claim records remote claimant and returns sign url" do
    post "/api/federation/v1/requests/#{@recipient.uuid}/claim",
         params: {
           claimant: {
             email: @recipient.email,
             displayName: "Remote user",
             externalUserId: "remote-123"
           }
         },
         headers: portal_headers(scope: "federation.request.claim")

    assert_response :created

    @recipient.reload
    assert_equal @recipient.email, @recipient.remote_claimed_by_email
    assert_not_nil @recipient.remote_claimed_at
    sign_url = response.parsed_body.fetch("claim").fetch("signUrl")
    assert_includes sign_url, "/bundles/#{@recipient.bundle.uuid}/sign?grant="
    assert response.parsed_body.fetch("claim").key?("expiresAt")

    get URI(sign_url).request_uri

    assert_response :success
    assert_includes response.body, @recipient.bundle.note
  end

  test "claim rejects email mismatch" do
    post "/api/federation/v1/requests/#{@recipient.uuid}/claim",
         params: {
           claimant: {
             email: "wrong@example.com"
           }
         },
         headers: portal_headers(scope: "federation.request.claim")

    assert_response :unprocessable_entity
  end

  test "preview rejects wrong portal" do
    other_key = OpenSSL::PKey::RSA.generate(2048)
    other_portal = PortalInstance.create!(
      name: "Other portal",
      base_url: "https://example.org",
      issuer: "https://other.example",
      public_key_pem: other_key.public_key.to_pem,
      allowed_email_domains: [ "other.example" ]
    )

    get "/api/federation/v1/requests/#{@recipient.uuid}",
        headers: portal_headers(scope: "federation.request.read", issuer: other_portal.issuer, key: other_key)

    assert_response :forbidden
  end

  test "withdrawn recipients revoke active grants" do
    post "/api/federation/v1/requests/#{@recipient.uuid}/claim",
         params: {
           claimant: {
             email: @recipient.email,
             displayName: "Remote user",
             externalUserId: "remote-123"
           }
         },
         headers: portal_headers(scope: "federation.request.claim")

    sign_url = response.parsed_body.fetch("claim").fetch("signUrl")
    @recipient.withdraw!

    get URI(sign_url).request_uri

    assert_response :not_found
  end

  private

  def create_federated_recipient(portal_instance)
    users(:one).update_column(:email, "owner@example.com")

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 federation test"),
      filename: "federation-test.pdf",
      content_type: "application/pdf"
    )

    contract = Contract.create!(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )

    bundle = Bundle.create!(author: users(:one), contracts: [ contract ], note: "Please sign")

    bundle.recipients.create!(
      email: "recipient@partner.example",
      locale: "en",
      portal_instance_uuid: portal_instance.uuid
    )
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
