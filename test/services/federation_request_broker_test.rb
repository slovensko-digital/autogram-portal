require "test_helper"

class FederationRequestBrokerTest < ActiveSupport::TestCase
  test "preview works for origin portal not present in local trusted list" do
    fake_client = Class.new do
      attr_reader :last_portal_instance

      def fetch_metadata(base_url:)
        {
          "issuer" => "https://origin.example",
          "baseUrl" => base_url,
          "portalName" => "Origin Portal",
          "capabilities" => {
            "requestPreview" => true,
            "requestClaim" => true
          }
        }
      end

      def fetch_request_preview(portal_instance:, recipient_uuid:, bundle_uuid:)
        @last_portal_instance = portal_instance

        {
          "originPortal" => { "name" => "Origin Portal" },
          "recipientId" => recipient_uuid,
          "bundleId" => bundle_uuid,
          "contracts" => []
        }
      end
    end.new

    broker = FederationRequestBroker.new(client: fake_client)
    preview = broker.preview(url: "https://example.com/bundles/bundle-1/sign?recipient=recipient-1")

    assert_equal "Origin Portal", preview.portal_instance.name
    assert_equal "https://example.com", fake_client.last_portal_instance.base_url
    assert_equal "https://example.com", preview.portal_instance.base_url
    assert_equal "recipient-1", preview.request.fetch("recipientId")
  end

  test "claim uses discovered issuer as JWT audience" do
    fake_client = Class.new do
      attr_reader :claimed_portal_instance

      def fetch_metadata(base_url:)
        {
          "issuer" => "https://federation-origin.example/issuer",
          "baseUrl" => base_url,
          "capabilities" => {
            "requestPreview" => true,
            "requestClaim" => true
          }
        }
      end

      def claim_request(portal_instance:, recipient_uuid:, bundle_uuid:, claimant:)
        @claimed_portal_instance = portal_instance
        "https://origin.example/bundles/#{bundle_uuid}/sign?grant=abc"
      end
    end.new

    broker = FederationRequestBroker.new(client: fake_client)
    sign_url = broker.claim(
      url: "https://example.com/bundles/bundle-1/sign?recipient=recipient-1",
      claimant: { email: "user@example.com", display_name: "User", external_user_id: "1" }
    )

    assert_equal "https://origin.example/bundles/bundle-1/sign?grant=abc", sign_url
    assert_equal "https://federation-origin.example/issuer", fake_client.claimed_portal_instance.issuer
  end

  test "preview rejects origin portals without federation capabilities" do
    fake_client = Class.new do
      def fetch_metadata(base_url:)
        {
          "issuer" => "https://origin.example",
          "baseUrl" => base_url,
          "capabilities" => {}
        }
      end
    end.new

    broker = FederationRequestBroker.new(client: fake_client)

    error = assert_raises(FederationRequestBroker::UnsupportedPortalError) do
      broker.preview(url: "https://example.com/bundles/bundle-1/sign?recipient=recipient-1")
    end

    assert_equal I18n.t("federation.requests.errors.unsupported_portal"), error.message
  end
end