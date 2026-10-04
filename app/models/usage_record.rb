# == Schema Information
#
# Table name: usage_records
#
#  id          :bigint           not null, primary key
#  kind        :string           not null
#  quantity    :integer          default(1), not null
#  source      :string           not null
#  created_at  :datetime         not null
#  contract_id :bigint
#  tenant_id   :bigint           not null
#
# Indexes
#
#  index_usage_records_on_contract_id                        (contract_id)
#  index_usage_records_on_signature_request_contract         (contract_id) UNIQUE WHERE ((kind)::text = 'signature_request'::text)
#  index_usage_records_on_tenant_id_and_kind_and_created_at  (tenant_id,kind,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id) ON DELETE => nullify
#  fk_rails_...  (tenant_id => tenants.id)
#
class UsageRecord < ApplicationRecord
  belongs_to :tenant
  belongs_to :contract, optional: true

  enum :kind, { signature_request: "signature_request", timestamp: "timestamp" }, validate: true
  enum :source, {
    notification: "notification",
    recipient_signature: "recipient_signature",
    extension: "extension",
    archivation: "archivation",
    avm_signing: "avm_signing"
  }, validate: true, prefix: true

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }

  scope :in_period, ->(period) { where(created_at: period) }
end
