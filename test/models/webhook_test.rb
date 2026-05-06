# == Schema Information
#
# Table name: webhooks
#
#  id         :bigint           not null, primary key
#  method     :integer          default("standard"), not null
#  url        :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bundle_id  :bigint           not null
#
# Indexes
#
#  index_webhooks_on_bundle_id  (bundle_id)
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#
require "test_helper"

class WebhookTest < ActiveSupport::TestCase
  test "rejects localhost webhook URLs" do
    webhook = Webhook.new(bundle: bundles(:one), url: "http://127.0.0.1/callback")

    assert_not webhook.valid?
    assert_includes webhook.errors[:url], "cannot target local or private addresses"
  end

  test "accepts public webhook URLs" do
    webhook = Webhook.new(bundle: bundles(:one), url: "https://1.1.1.1/callback")

    assert webhook.valid?
  end

  test "allowlist can explicitly permit internal destinations" do
    with_env("WEBHOOK_ALLOWED_HOSTS" => "localhost") do
      webhook = Webhook.new(bundle: bundles(:one), url: "http://localhost/callback")

      assert webhook.valid?
    end
  end

  private

  def with_env(vars)
    previous_values = {}
    vars.each_key { |key| previous_values[key] = ENV[key] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous_values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
