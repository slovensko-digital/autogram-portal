# == Schema Information
#
# Table name: contracts
#
#  id              :bigint           not null, primary key
#  allowed_methods :string           default([]), is an Array
#  uuid            :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  bundle_id       :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_contracts_on_bundle_id  (bundle_id)
#  index_contracts_on_user_id    (user_id)
#  index_contracts_on_uuid       (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (user_id => users.id)
#
class Contract < ApplicationRecord
  belongs_to :user
  belongs_to :bundle

  has_one :signature_parameters, class_name: "Ades::SignatureParameters", dependent: :destroy
  has_many :documents, dependent: :destroy

  ALLOWED_METHODS = %w[qualified advanced server].freeze

  validate :validate_allowed_methods

  private

  def validate_allowed_methods
    return if allowed_methods.blank?

    invalid_methods = allowed_methods - ALLOWED_METHODS
    errors.add(:allowed_methods, "contains invalid values: #{invalid_methods.join(', ')}") if invalid_methods.any?
  end
end
