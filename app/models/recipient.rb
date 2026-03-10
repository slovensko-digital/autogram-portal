# == Schema Information
#
# Table name: recipients
#
#  id                  :bigint           not null, primary key
#  email               :string           not null
#  locale              :string           default("sk"), not null
#  name                :string
#  notification_status :integer          default("not_notified"), not null
#  status              :integer          default("pending"), not null
#  uuid                :uuid             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  bundle_id           :bigint           not null
#  user_id             :bigint
#
# Indexes
#
#  index_recipients_on_bundle_id            (bundle_id)
#  index_recipients_on_bundle_id_and_email  (bundle_id,email) UNIQUE
#  index_recipients_on_email                (email)
#  index_recipients_on_status               (status)
#  index_recipients_on_user_id              (user_id)
#  index_recipients_on_uuid                 (uuid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (user_id => users.id)
#
class Recipient < ApplicationRecord
  has_one :recipient_signer, dependent: :destroy, class_name: "RecipientSigner", foreign_key: :recipient_id
  has_many :signer_contracts, through: :recipient_signer
  has_many :contracts, through: :signer_contracts
  has_many :sessions, through: :signer_contracts
  belongs_to :bundle
  belongs_to :user, optional: true

  enum :status, { pending: 0, declined: 3 }
  enum :notification_status, { not_notified: 0, sending: 1, notified: 2 }

  scope :signed_contract, ->(contract) {
    joins(recipient_signer: :signer_contracts)
      .where(signer_contracts: { contract_id: contract.id })
      .where.not(signer_contracts: { signed_at: nil })
      .distinct
  }
  scope :awaiting_contract, ->(contract) {
    joins(recipient_signer: :signer_contracts)
      .where(signer_contracts: { contract_id: contract.id, signed_at: nil })
      .distinct
  }

  before_validation :ensure_uuid, on: :create
  validates :uuid, presence: true, uniqueness: true
  validates :uuid, format: { with: /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/, message: "must be a valid UUID" }
  validates :email, presence: true, uniqueness: { scope: :bundle_id }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_nil: true

  before_create :link_user_by_email
  before_create :check_blocks
  before_create :set_default_locale
  after_create :associate_with_bundle_contracts

  def to_param
    uuid
  end

  def display_name
    name.presence || user&.display_name || email
  end

  def signed_contract?(contract)
    signer_contracts.where(contract: contract).where.not(signed_at: nil).exists?
  end

  def signed_contracts
    Contract.where(id: signer_contracts.where.not(signed_at: nil).select(:contract_id))
  end

  def unsigned_contracts
    Contract.where(id: signer_contracts.where(signed_at: nil).select(:contract_id))
  end

  def notifiable?
    return false if signed_contracts.exists?
    not_notified?
  end

  def notify!
    return unless notifiable?
    return unless bundle.author.feature_enabled?(:real_emails)

    sending!
    Notification::RecipientSignatureRequestedJob.perform_later(self)
  end

  def removable?
    return false if signed_contracts.exists?
    notifiable? || declined?
  end

  private

  def link_user_by_email
    self.user = User.find_by(email: email)
  end

  def check_blocks
    if RecipientBlock.blocked?(email)
      errors.add(:email, "is blocked")
      throw :abort
    end
  end

  def set_default_locale
    self.locale ||= user&.locale || I18n.default_locale.to_s
  end

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def associate_with_bundle_contracts
    return unless bundle.present? && bundle.contracts.any?

    recipient_signer = RecipientSigner.create_or_find_by!(recipient: self)
    now = Time.current
    SignerContract.insert_all(
      bundle.contracts.map { |c| { signer_id: recipient_signer.id, contract_id: c.id, created_at: now, updated_at: now } },
      unique_by: [ :signer_id, :contract_id ]
    )
  end
end
