# == Schema Information
#
# Table name: bundles
#
#  id                           :bigint           not null, primary key
#  author_notifications_enabled :boolean          default(FALSE), not null
#  note                         :text
#  publicly_visible             :boolean          default(FALSE), not null
#  required_signatures          :integer
#  signing_rule                 :string           default("all"), not null
#  uuid                         :string           not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  user_id                      :bigint           not null
#
# Indexes
#
#  index_bundles_on_user_id  (user_id)
#  index_bundles_on_uuid     (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class BundleTest < ActiveSupport::TestCase
  setup do
    @author = users(:one)
  end

  test "does not notify author by default" do
    bundle = Bundle.new(author: @author)

    assert_not bundle.should_notify_author?
  end

  test "notifies author when enabled for web bundles" do
    bundle = Bundle.new(author: @author, author_notifications_enabled: true)

    assert bundle.should_notify_author?
  end

  test "does not notify author for webhook-managed bundles even when enabled" do
    bundle = Bundle.new(author: @author, author_notifications_enabled: true)
    bundle.build_webhook(url: "https://example.com/webhook", method: :standard)

    assert_not bundle.should_notify_author?
  end
end
