# == Schema Information
#
# Table name: recipients
#
#  id                  :bigint           not null, primary key
#  author_proxy        :boolean          default(FALSE), not null
#  email               :string
#  locale              :string           default("sk"), not null
#  name                :string
#  notification_status :integer          default("not_notified"), not null
#  uuid                :uuid             not null
#  withdrawn_at        :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  bundle_id           :bigint           not null
#  user_id             :bigint
#
# Indexes
#
#  idx_on_bundle_id_author_proxy_withdrawn_at_dd4336f6ca  (bundle_id,author_proxy,withdrawn_at)
#  index_recipients_on_bundle_id                          (bundle_id)
#  index_recipients_on_bundle_id_and_email_active         (bundle_id,email) UNIQUE WHERE (withdrawn_at IS NULL)
#  index_recipients_on_bundle_id_and_withdrawn_at         (bundle_id,withdrawn_at)
#  index_recipients_on_email                              (email)
#  index_recipients_on_user_id                            (user_id)
#  index_recipients_on_uuid                               (uuid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

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
end
