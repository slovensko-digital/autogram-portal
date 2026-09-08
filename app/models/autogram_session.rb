# == Schema Information
#
# Table name: sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  error_message      :text
#  options            :jsonb
#  signing_started_at :datetime
#  status             :integer          default(0), not null
#  type               :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  signer_contract_id :bigint           not null
#
# Indexes
#
#  index_sessions_on_signer_contract_id  (signer_contract_id)
#  index_sessions_on_type                (type)
#
# Foreign Keys
#
#  fk_rails_...  (signer_contract_id => signer_contracts.id)
#
class AutogramSession < Session
  def self.model_name
    Session.model_name
  end

  def self.available?(qscd, contract)
    unavailability_reasons(qscd, contract).empty?
  end

  def self.unavailability_reasons(_qscd, contract)
    reasons = []
    reasons << :prepared_signature_fields if contract.prepared_signature_fields_source_attached?
    reasons
  end
end
