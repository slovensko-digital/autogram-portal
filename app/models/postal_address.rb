# == Schema Information
#
# Table name: postal_addresses
#
#  id             :bigint           not null, primary key
#  address        :text
#  recipient_name :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  bundle_id      :bigint           not null
#
# Indexes
#
#  index_postal_addresses_on_bundle_id  (bundle_id)
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#
class PostalAddress < ApplicationRecord
  belongs_to :bundle

  validates :address, presence: true
  validates :recipient_name, presence: true
end
