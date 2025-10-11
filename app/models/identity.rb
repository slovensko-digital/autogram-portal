# == Schema Information
#
# Table name: identities
#
#  id         :bigint           not null, primary key
#  provider   :string           not null
#  uid        :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_identities_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Identity < ApplicationRecord
  belongs_to :user

  validates :provider, presence: true, uniqueness: { scope: :user_id }
  validates :uid, presence: true, uniqueness: { scope: :provider }
end
