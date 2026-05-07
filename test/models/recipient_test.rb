# == Schema Information
#
# Table name: recipients
#
#  id                  :bigint           not null, primary key
#  email               :string           not null
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
#  index_recipients_on_bundle_id                   (bundle_id)
#  index_recipients_on_bundle_id_and_email_active  (bundle_id,email) UNIQUE WHERE (withdrawn_at IS NULL)
#  index_recipients_on_bundle_id_and_withdrawn_at  (bundle_id,withdrawn_at)
#  index_recipients_on_email                       (email)
#  index_recipients_on_user_id                     (user_id)
#  index_recipients_on_uuid                        (uuid) UNIQUE
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

  private

  def create_recipient(notification_status:, email: nil)
    recipient = bundles(:one).recipients.create!(
      email: email || "recipient-#{SecureRandom.hex(6)}@example.com",
      locale: "en"
    )

    recipient.update!(notification_status: notification_status)

    recipient
  end
end
