# == Schema Information
#
# Table name: signer_contracts
#
#  id            :bigint           not null, primary key
#  declined_at   :datetime
#  signed_at     :datetime
#  superseded_at :datetime
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  contract_id   :bigint           not null
#  signer_id     :bigint
#
# Indexes
#
#  index_signer_contracts_on_contract_and_signing_state  (contract_id,signed_at,declined_at)
#  index_signer_contracts_on_contract_id                 (contract_id)
#  index_signer_contracts_on_declined_at_not_null        (declined_at) WHERE (declined_at IS NOT NULL)
#  index_signer_contracts_on_signer_id                   (signer_id)
#  index_signer_contracts_on_signer_id_and_contract_id   (signer_id,contract_id) UNIQUE
#  index_signer_contracts_on_superseded_at_not_null      (superseded_at) WHERE (superseded_at IS NOT NULL)
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

  scope :awaiting,    -> { where(signed_at: nil, declined_at: nil, superseded_at: nil) }
  scope :declined,    -> { where.not(declined_at: nil) }
  scope :signed,      -> { where.not(signed_at: nil) }
  scope :superseded,  -> { where.not(superseded_at: nil) }

  def signed?
    signed_at.present?
  end

  def declined?
    declined_at.present?
  end

  def superseded?
    superseded_at.present?
  end

  def awaiting?
    signed_at.nil? && declined_at.nil? && superseded_at.nil?
  end

  def recipient
    signer.recipient if signer.is_a?(RecipientSigner)
  end
end
