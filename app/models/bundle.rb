# == Schema Information
#
# Table name: bundles
#
#  id         :bigint           not null, primary key
#  uuid       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_bundles_on_user_id  (user_id)
#  index_bundles_on_uuid     (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Bundle < ApplicationRecord
  belongs_to :author, class_name: "User", foreign_key: "user_id"

  has_many :contracts, dependent: :destroy
  has_and_belongs_to_many :recipients, class_name: "User", join_table: "bundles_recipients", association_foreign_key: "recipient_id"
  has_one :webhook, dependent: :destroy
  has_one :postal_address, dependent: :destroy

  validates :uuid, presence: true, uniqueness: true
  before_validation :ensure_uuid, on: :create

  # Use UUID in URLs instead of ID for security
  def to_param
    uuid
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
