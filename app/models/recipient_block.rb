# == Schema Information
#
# Table name: recipient_blocks
#
#  id         :bigint           not null, primary key
#  email      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_recipient_blocks_on_email  (email) UNIQUE
#
class RecipientBlock < ApplicationRecord
  validates :email, presence: true, uniqueness: true

  def self.blocked?(email)
    exists?(email: email)
  end

  def self.block(email)
    find_or_create_by(email: email)
  end
end
