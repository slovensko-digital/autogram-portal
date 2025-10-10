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
  # test "the truth" do
  #   assert true
  # end
end
