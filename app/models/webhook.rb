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
class Webhook < ApplicationRecord
  belongs_to :bundle
  enum :method, [ :standard, :get ]

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid URL" }

  def fire_contract_signed(contract)
    Rails.logger.info "Firing webhook for contract signed in bundle #{bundle.uuid}, contract #{contract.uuid}, webhook method #{method}, url #{url}"
    case method
    when "get"
      fire_get_webhook
    when "standard"
      fire_standard_webhook(
        { type: "contract.signed",
          timestamp: Time.now.iso8601,
          data: {
            contract_id: contract.uuid,
            bundle_id: bundle.uuid
          }
        }
      )
    end
  end

  def fire_all_signed
    case method
    when "get"
      fire_get_webhook
    when "standard"
      fire_standard_webhook(
        { type: "bundle.all_signed",
          timestamp: Time.now.iso8601,
          data: {
            bundle_id: bundle.uuid
          }
        }
      )
    end
  end

  private

  def fire_standard_webhook(payload)
    Rails.logger.info "Firing standard webhook to #{url} with payload: #{payload}"
    FireStandardWebhookJob.perform_later(url: url, webhook_id: Random.uuid, payload: payload)
  end

  def fire_get_webhook
    Rails.logger.info "Firing GET webhook to #{url}"
    FireGetWebhookJob.perform_later(url: url, webhook_id: Random.uuid)
  end
end
