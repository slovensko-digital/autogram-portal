# == Schema Information
#
# Table name: recipients
#
#  id                      :bigint           not null, primary key
#  author_proxy            :boolean          default(FALSE), not null
#  email                   :string
#  federation_mode         :string           default("local"), not null
#  locale                  :string           default("sk"), not null
#  mobile_phone            :string
#  name                    :string
#  notification_status     :integer          default("not_notified"), not null
#  remote_claimed_at       :datetime
#  remote_claimed_by_email :string
#  uuid                    :uuid             not null
#  withdrawn_at            :datetime
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  bundle_id               :bigint           not null
#  portal_instance_id      :bigint
#  user_id                 :bigint
#
# Indexes
#
#  idx_on_bundle_id_author_proxy_withdrawn_at_dd4336f6ca  (bundle_id,author_proxy,withdrawn_at)
#  index_recipients_on_bundle_id                          (bundle_id)
#  index_recipients_on_bundle_id_and_email_active         (bundle_id,email) UNIQUE WHERE (withdrawn_at IS NULL)
#  index_recipients_on_bundle_id_and_withdrawn_at         (bundle_id,withdrawn_at)
#  index_recipients_on_email                              (email)
#  index_recipients_on_federation_mode                    (federation_mode)
#  index_recipients_on_portal_instance_id                 (portal_instance_id)
#  index_recipients_on_user_id                            (user_id)
#  index_recipients_on_uuid                               (uuid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (portal_instance_id => portal_instances.id)
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"
require "openssl"

class RecipientTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    users(:one).update_column(:email, "owner@example.com")
  end

  teardown do
    clear_enqueued_jobs
    ActiveJob::Base.queue_adapter = @queue_adapter
  end

  test "withdraw marks recipient withdrawn and supersedes pending signer contracts" do
    recipient = create_recipient(notification_status: :notified)

    assert_enqueued_with(job: Notification::RecipientSignatureWithdrawnJob) do
      assert recipient.withdraw!
    end

    recipient.reload

    assert recipient.withdrawn?
    assert_not recipient.pending?
    assert_not recipient.removable?
    assert recipient.signer_contracts.where(signed_at: nil, superseded_at: nil).none?
  end

  test "withdraw does not enqueue email when recipient was never notified" do
    recipient = create_recipient(notification_status: :not_notified)

    assert_no_enqueued_jobs only: Notification::RecipientSignatureWithdrawnJob do
      recipient.withdraw!
    end
  end

  test "withdraw revokes active access grants" do
    recipient = create_recipient(notification_status: :not_notified)
    portal_instance = create_portal_instance
    grant = RecipientAccessGrant.issue!(
      recipient: recipient,
      portal_instance: portal_instance,
      claimed_by_email: recipient.email,
      claimed_by_external_user_id: "remote-123",
      claim_jti: SecureRandom.hex(16)
    )

    recipient.withdraw!

    assert_not grant.reload.active?
    assert_not_nil grant.revoked_at
  end

  test "notify enqueues portal invitation job for federated recipients" do
    portal_instance = create_portal_instance
    recipient = bundles(:one).recipients.create!(
      email: "recipient@example.com",
      locale: "en",
      portal_instance_uuid: portal_instance.uuid
    )

    assert_enqueued_with(job: Federation::SendRequestInvitationJob, args: [ recipient ]) do
      recipient.notify!
    end

    assert recipient.reload.sending?
  end

  test "withdraw enqueues portal invitation withdrawal for remotely notified federated recipients" do
    portal_instance = create_portal_instance
    recipient = bundles(:one).recipients.create!(
      email: "recipient@example.com",
      locale: "en",
      portal_instance_uuid: portal_instance.uuid
    )
    recipient.update!(notification_status: :notified, remote_notified_at: Time.current)

    assert_enqueued_with(job: Federation::WithdrawRequestInvitationJob, args: [ recipient, { status: "withdrawn" } ]) do
      recipient.withdraw!
    end
  end

  test "same email can be added again after withdrawal" do
    email = "recipient-#{SecureRandom.hex(6)}@example.com"
    recipient = create_recipient(notification_status: :notified, email: email)
    recipient.withdraw!

    new_recipient = recipient.bundle.recipients.create!(email: email, locale: "en")

    assert new_recipient.persisted?
    assert new_recipient.active?
  end

  test "email is required by default" do
    recipient = bundles(:one).recipients.build(email: nil, locale: "en")

    assert_not recipient.valid?
    assert recipient.errors.of_kind?(:email, :blank)
  end

  test "email can be blank when bundle allows blank recipient emails" do
    bundle = bundles(:one)
    bundle.allow_blank_recipient_emails = true

    recipient = bundle.recipients.create!(email: nil, locale: "en")

    assert recipient.persisted?
    assert_nil recipient.email
  end

  test "mobile phone is normalized to e164" do
    recipient = bundles(:one).recipients.create!(
      email: "recipient.mobile@example.com",
      mobile_phone: "00421 901 234 567",
      locale: "en"
    )

    assert_equal "+421901234567", recipient.mobile_phone
    assert_equal "+421***567", recipient.masked_mobile_phone
  end

  test "mobile phone must use e164 format after normalization" do
    recipient = bundles(:one).recipients.build(
      email: "recipient.invalid@example.com",
      mobile_phone: "1234",
      locale: "en"
    )

    assert_not recipient.valid?
    assert_includes recipient.errors[:mobile_phone], "must be in E.164 format"
  end

  test "local recipients still link to an existing user by email" do
    users(:two).update_column(:email, "recipient@example.com")

    recipient = bundles(:one).recipients.create!(email: "recipient@example.com", locale: "en")

    assert_equal users(:two), recipient.user
    assert recipient.local_recipient?
    assert_nil recipient.portal_instance
  end

  test "federated recipients resolve portal instance and skip local user linking" do
    users(:two).update_column(:email, "recipient@example.com")
    portal_instance = create_portal_instance

    recipient = bundles(:one).recipients.create!(
      email: "recipient@example.com",
      locale: "en",
      portal_instance_uuid: portal_instance.uuid
    )

    assert recipient.federated_recipient?
    assert_equal portal_instance, recipient.portal_instance
    assert_nil recipient.user
  end

  test "federated recipients require a verified portal instance" do
    portal_instance = create_portal_instance(status: "revoked")
    recipient = bundles(:one).recipients.build(
      email: "recipient@example.com",
      locale: "en",
      portal_instance_uuid: portal_instance.uuid
    )

    assert_not recipient.valid?
    assert_includes recipient.errors[:portal_instance], "must be verified"
  end

  test "find_or_create_author_proxy_for creates a hidden recipient" do
    bundle = create_bundle_with_contract

    recipient = Recipient.find_or_create_author_proxy_for!(bundle: bundle, user: users(:one))

    assert recipient.author_proxy?
    assert_not recipient.visible?
    assert_equal [ recipient ], bundle.recipients.author_proxies.to_a
    assert_empty bundle.visible_recipients
  end

  test "find_or_create_author_proxy_for reuses an existing visible recipient" do
    bundle = create_bundle_with_contract
    visible_recipient = bundle.recipients.create!(email: users(:one).email, user: users(:one), locale: "sk")

    recipient = Recipient.find_or_create_author_proxy_for!(bundle: bundle, user: users(:one))

    assert_equal visible_recipient, recipient
    assert_not recipient.author_proxy?
    assert_equal 1, bundle.recipients.active.where(email: users(:one).email).count
  end

  test "find_or_create_author_proxy_for returns the created recipient after a duplicate key race" do
    bundle = create_bundle_with_contract
    recipients = bundle.recipients
    created_recipient = nil

    recipients.singleton_class.alias_method :__original_create_for_race_test, :create!
    recipients.singleton_class.define_method(:create!) do |*args, **kwargs, &block|
      created_recipient ||= __original_create_for_race_test(*args, **kwargs, &block)
      raise ActiveRecord::RecordNotUnique, "duplicate recipient"
    end

    recipient = Recipient.find_or_create_author_proxy_for!(bundle: bundle, user: users(:one))

    assert_equal created_recipient, recipient
    assert recipient.author_proxy?
    assert_equal 1, bundle.recipients.active.where(email: users(:one).email).count
  ensure
    recipients.singleton_class.alias_method :create!, :__original_create_for_race_test
    recipients.singleton_class.remove_method :__original_create_for_race_test
  end

  private

  def create_bundle_with_contract
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "recipient-test.pdf",
      content_type: "application/pdf"
    )

    contract = Contract.create!(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )

    Bundle.create!(author: users(:one), contracts: [ contract ])
  end

  def create_recipient(notification_status:, email: nil)
    recipient = bundles(:one).recipients.create!(
      email: email || "recipient-#{SecureRandom.hex(6)}@example.com",
      locale: "en"
    )

    recipient.update!(notification_status: notification_status)

    recipient
  end

  def create_portal_instance(**attributes)
    PortalInstance.create!({
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://issuer.example.com/#{SecureRandom.hex(4)}",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem,
      allowed_email_domains: [ "example.com" ]
    }.merge(attributes))
  end
end
