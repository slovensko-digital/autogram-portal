# == Schema Information
#
# Table name: signer_contracts
#
#  id          :bigint           not null, primary key
#  signed_at   :datetime
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  contract_id :bigint           not null
#  signer_id   :bigint
#
# Indexes
#
#  index_signer_contracts_on_contract_id                (contract_id)
#  index_signer_contracts_on_signer_id                  (signer_id)
#  index_signer_contracts_on_signer_id_and_contract_id  (signer_id,contract_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (signer_id => signers.id)
#
class SignerContract < ApplicationRecord
  belongs_to :signer
  belongs_to :contract
  has_many :sessions, dependent: :destroy

  validates :signer, uniqueness: { scope: :contract_id }

  def signed?
    signed_at.present?
  end

  # Convenience — nil for UserSigner-backed contracts
  def recipient
    signer.recipient if signer.is_a?(RecipientSigner)
  end
end
