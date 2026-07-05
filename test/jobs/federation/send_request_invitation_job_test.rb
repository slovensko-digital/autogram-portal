require "test_helper"
require "openssl"

class Federation::SendRequestInvitationJobTest < ActiveJob::TestCase
  setup do
    users(:one).update_column(:email, "owner@example.com")
  end

  test "perform sends invitation to recipient portal and marks recipient notified" do
    recipient = create_federated_recipient
    recipient.update!(notification_status: :sending)
    fake_client = SendClientStub.new

    with_federation_portal_client(fake_client) do
      Federation::SendRequestInvitationJob.perform_now(recipient)
    end

    recipient.reload

    assert recipient.notified?
    assert_not_nil recipient.remote_notified_at
    assert_equal recipient.portal_instance, fake_client.portal_instance
    assert_equal recipient.uuid, fake_client.invitation.fetch(:recipientId)
    assert_equal recipient.bundle.uuid, fake_client.invitation.fetch(:bundleId)
    assert_includes fake_client.invitation.fetch(:openUrl), "/bundles/#{recipient.bundle.uuid}/sign?recipient=#{recipient.uuid}"
  end

  test "perform withdraw sends withdrawal to recipient portal" do
    recipient = create_federated_recipient
    recipient.update!(remote_notified_at: Time.current)
    fake_client = WithdrawClientStub.new

    with_federation_portal_client(fake_client) do
      Federation::WithdrawRequestInvitationJob.perform_now(recipient)
    end

    assert_equal recipient.portal_instance, fake_client.portal_instance
    assert_equal recipient.uuid, fake_client.recipient_uuid
  end

  private

  SendClientStub = Struct.new(:portal_instance, :invitation) do
    def initialize
      super(nil, nil)
    end

    def send_request_invitation(portal_instance:, invitation:)
      self.portal_instance = portal_instance
      self.invitation = invitation
      { "id" => SecureRandom.uuid }
    end
  end

  WithdrawClientStub = Struct.new(:portal_instance, :recipient_uuid) do
    def initialize
      super(nil, nil)
    end

    def withdraw_request_invitation(portal_instance:, recipient_uuid:)
      self.portal_instance = portal_instance
      self.recipient_uuid = recipient_uuid
      { "id" => SecureRandom.uuid }
    end
  end

  def create_federated_recipient
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 federation job test"),
      filename: "federation-job-test.pdf",
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
    portal_instance = PortalInstance.create!(
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://partner.example/#{SecureRandom.hex(4)}",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem,
      allowed_email_domains: [ "example.com" ]
    )

    bundle.recipients.create!(
      email: "recipient@example.com",
      locale: "en",
      portal_instance_uuid: portal_instance.uuid
    )
  end

  def with_federation_portal_client(fake_client)
    client_singleton = FederationPortalClient.singleton_class
    client_singleton.send(:alias_method, :__original_new_for_test, :new)
    client_singleton.send(:define_method, :new) { fake_client }

    yield
  ensure
    client_singleton.send(:remove_method, :new)
    client_singleton.send(:alias_method, :new, :__original_new_for_test)
    client_singleton.send(:remove_method, :__original_new_for_test)
  end
end