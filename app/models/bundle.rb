# == Schema Information
#
# Table name: bundles
#
#  id         :bigint           not null, primary key
#  note       :text
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
  has_many :recipients, dependent: :destroy
  has_one :webhook, dependent: :destroy
  has_one :postal_address, dependent: :destroy

  accepts_nested_attributes_for :contracts, allow_destroy: true
  accepts_nested_attributes_for :webhook, allow_destroy: true
  accepts_nested_attributes_for :postal_address, allow_destroy: true
  accepts_nested_attributes_for :recipients, allow_destroy: true

  before_validation :ensure_uuid, on: :create
  validates :uuid, presence: true, uniqueness: true
  validates :uuid, format: { with: /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/, message: "must be a valid UUID" }
  validates :contracts, presence: true

  after_create :notify_recipients

  def to_param
    uuid
  end

  def completed?
     return recipients.signed.count == recipients.count if recipients.count.positive?
     contracts.all? { !it.awaiting_signature? }
  end

  def awaiting_recipients?(contract: nil)
    # TODO: consider recipients per contract scenario
    recipients.notified.count.positive?
  end

  def contract_signed(contract)
    # TODO: add logic to handle multiple recipients signing their respective contracts
    recipients.notified.first.update(status: :signed) if recipients.notified.any?

    Notification::BundleContractSignedJob.perform_later(self, contract)
    return unless completed?

    Notification::BundleCompletedJob.perform_later(self)
    broadcast_all_signed
  end

  def broadcast_all_signed
    Turbo::StreamsChannel.broadcast_replace_to(
      self,
      target: "bundle_#{id}_status",
      partial: "bundles/status",
      locals: { bundle: self }
    )
  end

  def should_notify_author?
    # TODO: do not notify if author is the one that signed the bundle
    true
  end

  def notify_recipients
    return unless author.feature_enabled?(:real_emails)

    recipients.each(&:notify!)
  end

  def short_uuid
    uuid.first(8)
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
