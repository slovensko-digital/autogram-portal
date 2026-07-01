# == Schema Information
#
# Table name: sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  error_message      :text
#  options            :jsonb
#  signing_started_at :datetime
#  status             :integer          default("pending"), not null
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
class PodpisujSession < Session
  def self.model_name
    Session.model_name
  end

  def self.available?(qscd, contract)
    return false if contract.documents.count > 1
    return false if contract.prepared_signature_fields_source_attached?
    contract.signature_parameters.level == "BASELINE_B"
  end
end
