# == Schema Information
#
# Table name: bundles
#
#  id                           :bigint           not null, primary key
#  author_notifications_enabled :boolean          default(FALSE), not null
#  name                         :string
#  note                         :text
#  publicly_visible             :boolean          default(FALSE), not null
#  required_signatures          :integer
#  signing_rule                 :string           default("all"), not null
#  uuid                         :string           not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  tenant_id                    :bigint           not null
#
# Indexes
#
#  index_bundles_on_tenant_id  (tenant_id)
#  index_bundles_on_uuid       (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id)
#
require "test_helper"
require "openssl"

class BundleTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @author = users(:one)
    @author.update_column(:email, "owner@example.com")
    @queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
  end

  teardown do
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @queue_adapter
  end

  test "author proxy recipients do not count as bundle recipients" do
    bundle = create_bundle_with_contract(author: @author)

    Recipient.find_or_create_author_proxy_for!(bundle: bundle, user: @author)

    assert_empty bundle.visible_recipients
    assert_empty bundle.active_recipients
    assert_equal :no_recipients, bundle.bundle_state
    assert_not bundle.completed?
  end

  test "does not notify author by default" do
    bundle = Bundle.new(tenant: @author.tenants.sole)

    assert_not bundle.should_notify_author?
  end

  test "display name uses the custom name when present and falls back when blank" do
    bundle = Bundle.new(tenant: @author.tenants.sole, uuid: "12345678-1234-1234-1234-123456789abc")
    default_name = "#{I18n.t('bundles.display_name')} 12345678"

    assert_equal default_name, bundle.display_name

    bundle.name = "Employment agreement"
    assert_equal "Employment agreement", bundle.display_name

    bundle.name = ""
    assert_equal default_name, bundle.display_name
  end

  test "notifies author when enabled for web bundles" do
    bundle = Bundle.new(tenant: @author.tenants.sole, author_notifications_enabled: true)

    assert bundle.should_notify_author?
  end

  test "tenant is the sender and its owners get author notifications except the signer" do
    tenant = @author.tenants.sole
    tenant.update!(plan: :pro)
    co_owner = users(:two)
    tenant.memberships.create!(user: co_owner, role: :owner)
    bundle = Bundle.new(tenant: tenant)

    assert_equal tenant.name, bundle.sender_display_name
    assert_equal [ @author, co_owner ].sort_by(&:id), bundle.tenant.notification_recipients.sort_by(&:id)
    assert_equal [ co_owner ], bundle.tenant.notification_recipients(except: @author)
  end

  test "basic tenant sender shows the owner name and email" do
    bundle = Bundle.new(tenant: @author.tenants.sole)

    @author.update_column(:name, "Marek Celuch")
    assert_equal "Marek Celuch - #{@author.email}", bundle.sender_display_name

    @author.update_column(:name, nil)
    assert_equal @author.email, bundle.sender_display_name
  end

  test "does not notify author for webhook-managed bundles even when enabled" do
    bundle = Bundle.new(tenant: @author.tenants.sole, author_notifications_enabled: true)
    bundle.build_webhook(url: "https://example.com/webhook", method: :standard)

    assert_not bundle.should_notify_author?
  end

  test "author signing one contract does not enqueue signature no longer required notification" do
    bundle = create_bundle_with_contracts(author: @author, count: 3)
    author_proxy = Recipient.find_or_create_author_proxy_for!(bundle: bundle, user: @author)
    signer_contract = author_proxy.signer_contracts.find_by!(contract: bundle.contracts.first)
    signer_contract.update!(signed_at: Time.current)

    assert_no_enqueued_jobs only: Notification::RecipientNoLongerRequiredJob do
      bundle.notify_contract_signed(bundle.contracts.first, nil)
    end
  end

  test "sms verification is available when any contract allows ades and sms delivery is configured" do
    bundle = create_bundle_with_contracts(author: @author, count: 2)

    assert_not bundle.sms_verification_available?

    bundle.contracts.last.update!(allowed_methods: [ "qes", "ades" ])

    assert bundle.reload.sms_verification_available?

    without_sms_provider do
      assert_not bundle.sms_verification_available?
    end
  end

  test "superseding recipients revokes their active access grants" do
    bundle = create_bundle_with_contract(author: @author)
    bundle.update!(signing_rule: "any")

    first_recipient = bundle.recipients.create!(email: "first@example.com", locale: "en")
    second_recipient = bundle.recipients.create!(email: "second@example.com", locale: "en")
    portal_instance = create_portal_instance

    grant = RecipientAccessGrant.issue!(
      recipient: second_recipient,
      portal_instance: portal_instance,
      claimed_by_email: second_recipient.email,
      claimed_by_external_user_id: "remote-123",
      claim_jti: SecureRandom.hex(16)
    )

    first_recipient.signer_contracts.find_by!(contract: bundle.contracts.first).update!(signed_at: Time.current)

    bundle.notify_contract_signed(bundle.contracts.first, nil)

    assert_not grant.reload.active?
    assert_not_nil grant.revoked_at
  end

  test "signing the final contract for a federated recipient withdraws the portal invitation" do
    bundle = create_bundle_with_contract(author: @author)
    portal_instance = create_portal_instance
    recipient = bundle.recipients.create!(
      email: "recipient@example.com",
      locale: "en",
      portal_instance_uuid: portal_instance.uuid
    )
    recipient.update!(remote_notified_at: Time.current)
    signer_contract = recipient.signer_contracts.find_by!(contract: bundle.contracts.first)
    signer_contract.update!(signed_at: Time.current)

    assert_enqueued_with(job: Federation::WithdrawRequestInvitationJob, args: [ recipient, { status: "signed" } ]) do
      bundle.notify_contract_signed(bundle.contracts.first, recipient.recipient_signer)
    end
  end

  test "superseding a federated recipient withdraws the portal invitation" do
    bundle = create_bundle_with_contract(author: @author)
    bundle.update!(signing_rule: "any")

    first_recipient = bundle.recipients.create!(email: "first@example.com", locale: "en")
    second_recipient = bundle.recipients.create!(
      email: "second@example.com",
      locale: "en",
      portal_instance_uuid: create_portal_instance.uuid
    )
    second_recipient.update!(remote_notified_at: Time.current)

    first_recipient.signer_contracts.find_by!(contract: bundle.contracts.first).update!(signed_at: Time.current)

    assert_enqueued_with(job: Federation::WithdrawRequestInvitationJob, args: [ second_recipient, { status: "superseded" } ]) do
      bundle.notify_contract_signed(bundle.contracts.first, first_recipient.recipient_signer)
    end
  end

  private

  def create_bundle_with_contract(author:)
    create_bundle_with_contracts(author: author, count: 1)
  end

  def create_bundle_with_contracts(author:, count:)
    contracts = count.times.map do |index|
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("%PDF-1.4 test content #{index}"),
        filename: "bundle-test-#{index}.pdf",
        content_type: "application/pdf"
      )

      Contract.create!(
        documents_attributes: [ { blob: blob } ],
        signature_parameters_attributes: {
          level: "BASELINE_B",
          format: "PAdES"
        }
      )
    end

    Bundle.create!(tenant: author.tenants.sole, contracts: contracts)
  end

  def create_portal_instance
    PortalInstance.create!(
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://issuer.example.com/#{SecureRandom.hex(4)}",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem,
      allowed_email_domains: [ "example.com" ]
    )
  end

  def without_sms_provider
    environment_singleton = AutogramEnvironment.singleton_class
    original_sms_provider = AutogramEnvironment.method(:sms_provider)
    environment_singleton.define_method(:sms_provider) { nil }

    yield
  ensure
    environment_singleton.define_method(:sms_provider) { original_sms_provider.call }
  end
end
