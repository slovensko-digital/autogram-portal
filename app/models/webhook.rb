# == Schema Information
#
# Table name: webhooks
#
#  id         :bigint           not null, primary key
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
class Webhook < ApplicationRecord
  belongs_to :bundle

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL" }
end
