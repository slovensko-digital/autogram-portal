# == Schema Information
#
# Table name: bundles
#
#  id               :bigint           not null, primary key
#  note             :text
#  publicly_visible :boolean          default(FALSE), not null
#  uuid             :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :bigint           not null
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

  scope :publicly_visible, -> { where(publicly_visible: true) }

  def to_param
    uuid
  end

  def completed?
     return awaiting_recipients? if recipients.count.positive?
     contracts.all? { !it.awaiting_signature? }
  end

  def awaiting_recipients?(contract: nil)
    # TODO: consider recipients per contract scenario
    recipients.notified.count.positive?
  end

  def notify_contract_signed(contract, recipient)
    Notification::BundleContractSignedJob.perform_later(self, contract, signer: recipient)
    return unless completed?

    Notification::BundleCompletedJob.perform_later(self)

    Turbo::StreamsChannel.broadcast_replace_to(
      self,
      target: "bundle_#{uuid}_status",
      partial: "bundles/status",
      locals: { bundle: self }
    )
  end

  def should_notify_author?(contract: nil, signer: nil)
    if signer
      return false if author == signer.user
    end

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
