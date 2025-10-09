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

  accepts_nested_attributes_for :contracts, allow_destroy: true
  accepts_nested_attributes_for :webhook, allow_destroy: true
  accepts_nested_attributes_for :postal_address, allow_destroy: true
  accepts_nested_attributes_for :recipients, allow_destroy: true

  before_validation :ensure_uuid, on: :create
  validates :uuid, presence: true, uniqueness: true
  validates :contracts, presence: true

  # Use UUID in URLs instead of ID for security
  def to_param
    uuid
  end

  def completed?
    contracts.all? { |c| !c.awaiting_signature? }
  end

  def contract_signed(contract)
    Rails.logger.info "Contract #{contract.uuid} in bundle #{uuid} signed. Checking if bundle is completed..."
    if completed?
      Rails.logger.info "Bundle #{uuid} completed. Broadcasting all signed."
      broadcast_all_signed
    else
      Rails.logger.info "Bundle #{uuid} not yet completed. Broadcasting contract signed."
      broadcast_contract_signed(contract)
    end
  end

  def broadcast_all_signed
    Turbo::StreamsChannel.broadcast_replace_to(
      self,
      target: "bundle_#{id}_status",
      partial: "bundles/status",
      locals: { bundle: self }
    )

    webhook.fire_all_signed() if webhook.present?
  end

  def broadcast_contract_signed(contract)
    webhook.fire_contract_signed(contract) if webhook.present?
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
