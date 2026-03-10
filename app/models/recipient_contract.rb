# == Schema Information
#
# Table name: recipient_contracts
#
#  id           :bigint           not null, primary key
#  signed_at    :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  contract_id  :bigint           not null
#  recipient_id :bigint           not null
#
# Indexes
#
#  index_recipient_contracts_on_contract_id                   (contract_id)
#  index_recipient_contracts_on_recipient_id                  (recipient_id)
#  index_recipient_contracts_on_recipient_id_and_contract_id  (recipient_id,contract_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (recipient_id => recipients.id)
#
class RecipientContract < ApplicationRecord
  belongs_to :recipient
  belongs_to :contract
  has_many :sessions, dependent: :nullify

  validates :recipient, uniqueness: { scope: :contract_id }

  def signed?
    signed_at.present?
  end
end
