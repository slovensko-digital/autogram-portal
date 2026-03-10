# == Schema Information
#
# Table name: signers
#
#  id           :bigint           not null, primary key
#  type         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  recipient_id :bigint
#  user_id      :bigint
#
# Indexes
#
#  index_signers_on_recipient_id                               (recipient_id)
#  index_signers_on_recipient_id_unique_for_recipient_signers  (recipient_id) UNIQUE WHERE (((type)::text = 'RecipientSigner'::text) AND (recipient_id IS NOT NULL))
#  index_signers_on_user_id                                    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (recipient_id => recipients.id)
#  fk_rails_...  (user_id => users.id)
#
class RecipientSigner < Signer
  validates :recipient, presence: true
  validates :recipient, uniqueness: true

  def user
    recipient&.user
  end

  def display_name
    recipient.display_name
  end
end
