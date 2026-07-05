# == Schema Information
#
# Table name: recipients
#
#  id                      :bigint           not null, primary key
#  author_proxy            :boolean          default(FALSE), not null
#  email                   :string
#  federation_mode         :string           default("local"), not null
#  locale                  :string           default("sk"), not null
#  mobile_phone            :string
#  name                    :string
#  notification_status     :integer          default("not_notified"), not null
#  remote_claimed_at       :datetime
#  remote_claimed_by_email :string
#  uuid                    :uuid             not null
#  withdrawn_at            :datetime
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  bundle_id               :bigint           not null
#  portal_instance_id      :bigint
#  user_id                 :bigint
#
# Indexes
#
#  idx_on_bundle_id_author_proxy_withdrawn_at_dd4336f6ca  (bundle_id,author_proxy,withdrawn_at)
#  index_recipients_on_bundle_id                          (bundle_id)
#  index_recipients_on_bundle_id_and_email_active         (bundle_id,email) UNIQUE WHERE (withdrawn_at IS NULL)
#  index_recipients_on_bundle_id_and_withdrawn_at         (bundle_id,withdrawn_at)
#  index_recipients_on_email                              (email)
#  index_recipients_on_federation_mode                    (federation_mode)
#  index_recipients_on_portal_instance_id                 (portal_instance_id)
#  index_recipients_on_user_id                            (user_id)
#  index_recipients_on_uuid                               (uuid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (portal_instance_id => portal_instances.id)
#  fk_rails_...  (user_id => users.id)
#
class Recipient < ApplicationRecord
  MOBILE_PHONE_FORMAT = /\A\+[1-9]\d{7,14}\z/

  attr_accessor :portal_instance_uuid

  has_one :recipient_signer, dependent: :destroy, class_name: "RecipientSigner", foreign_key: :recipient_id
  has_many :signature_field_preparations, dependent: :destroy
  has_many :signer_contracts, through: :recipient_signer
  has_many :contracts, through: :signer_contracts
  has_many :sessions, through: :signer_contracts
  has_many :recipient_access_grants, dependent: :destroy
  belongs_to :bundle
  belongs_to :user, optional: true
  belongs_to :portal_instance, optional: true

  encrypts :mobile_phone

  enum :federation_mode, { local: "local", federated: "federated" }, scopes: false
  enum :notification_status, { not_notified: 0, sending: 1, notified: 2 }, scopes: false

  scope :active, -> { where(withdrawn_at: nil) }
  scope :withdrawn, -> { where.not(withdrawn_at: nil) }
  scope :visible, -> { where(author_proxy: false) }
  scope :author_proxies, -> { where(author_proxy: true) }

  scope :awaiting_contract, ->(contract) {
    joins(recipient_signer: :signer_contracts)
      .where(signer_contracts: { contract_id: contract.id, signed_at: nil, declined_at: nil, superseded_at: nil })
      .distinct
  }

  before_validation :ensure_uuid, on: :create
  before_validation :normalize_mobile_phone
  validates :uuid, presence: true, uniqueness: true
  validates :uuid, format: { with: /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/, message: "must be a valid UUID" }
  validates :email,
    presence: true,
    unless: :allow_blank_email?
  validates :email,
    uniqueness: { scope: :bundle_id, conditions: -> { where(withdrawn_at: nil) } },
    format: { with: URI::MailTo::EMAIL_REGEXP },
    allow_blank: true
  validates :mobile_phone,
    format: { with: MOBILE_PHONE_FORMAT, message: "must be in E.164 format" },
    allow_blank: true
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_nil: true
  validate :portal_instance_reference_must_exist
  validate :portal_instance_must_be_verified, if: -> { portal_instance.present? }
  validate :portal_instance_matches_federation_mode
  validate :federated_recipient_cannot_have_local_user

  before_create :link_user_by_email
  before_validation :assign_identity, on: :create
  before_create :check_blocks
  before_create :set_default_locale
  after_create :associate_with_bundle_contracts
  after_create :recompute_bundle_superseded_state

  def self.find_or_create_author_proxy_for!(bundle:, user:)
    existing_recipient = bundle.recipients.active.find_by(user: user) ||
      bundle.recipients.active.find_by(email: user.email)
    return existing_recipient if existing_recipient

    bundle.recipients.create!(
      email: user.email,
      user: user,
      name: user.display_name,
      author_proxy: true
    )
  rescue ActiveRecord::RecordNotUnique
    bundle.recipients.active.find_by!(email: user.email)
  end

  def to_param
    uuid
  end

  def display_name
    name.presence || user&.display_name || email
  end

  def mobile_phone?
    mobile_phone.present?
  end

  def masked_mobile_phone
    return if mobile_phone.blank?

    "#{mobile_phone.first(4)}***#{mobile_phone.last(3)}"
  end

  def active?
    !withdrawn?
  end

  def withdrawn?
    withdrawn_at.present?
  end

  def visible?
    !author_proxy?
  end

  def local_recipient?
    federation_mode == "local"
  end

  def federated_recipient?
    federation_mode == "federated"
  end

  def revoke_active_access_grants!
    recipient_access_grants.active.update_all(revoked_at: Time.current, updated_at: Time.current)
  end

  def signed_contract?(contract)
    signer_contracts.find_by!(contract: contract).signed?
  end

  def declined_contract?(contract)
    signer_contracts.find_by!(contract: contract).declined?
  end

  def pending_contract?(contract)
    signer_contracts.find_by!(contract: contract).awaiting?
  end

  def pending?
    return false if withdrawn?
    signer_contracts.awaiting.exists?
  end

  def declined?
    return false if withdrawn?
    signer_contracts.declined.exists?
  end

  def superseded?
    return false if withdrawn?
    signer_contracts.superseded.exists? && !signer_contracts.signed.exists? && !pending?
  end

  def signed?
    return false if withdrawn?
    signer_contracts.exists? && !pending? && !declined?
  end

  def notifiable?
    return false if withdrawn?
    return false if signer_contracts.signed.exists?
    return false if superseded?
    not_notified?
  end

  def notify!
    return unless notifiable?

    sending!

    if federated_recipient?
      Federation::SendRequestInvitationJob.perform_later(self)
    else
      Notification::RecipientSignatureRequestedJob.perform_later(self)
    end
  end

  def removable?
    return false if withdrawn?
    return false if signer_contracts.signed.exists?
    true
  end

  def withdraw!
    return false unless removable?

    transaction do
      now = Time.current
      signer_contracts.where(signed_at: nil).update_all(declined_at: nil, superseded_at: now, updated_at: now)
      update!(withdrawn_at: now)
      revoke_active_access_grants!
      Federation::WithdrawRequestInvitationJob.perform_later(self, status: "withdrawn") if federated_recipient? && remote_notified_at.present?
      Notification::RecipientSignatureWithdrawnJob.perform_later(self) if notified?
    end

    true
  end

  private

  def normalize_mobile_phone
    normalized_phone = mobile_phone.to_s.strip
    normalized_phone = normalized_phone.gsub(/[\s\-()]/, "")
    normalized_phone = "+#{normalized_phone.delete_prefix('00')}" if normalized_phone.start_with?("00")

    self.mobile_phone = normalized_phone.presence
  end

  def assign_identity
    RecipientResolver.assign_identity(self)
  end

  def allow_blank_email?
    email.blank? && bundle&.allow_blank_recipient_emails
  end

  def link_user_by_email
    return unless local_recipient?
    return if email.blank? || user.present?

    self.user = User.find_by(email: email)
  end

  def check_blocks
    return if email.blank?

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

    recipient_signer = recipient_signer || create_recipient_signer!
    now = Time.current
    SignerContract.insert_all(
      bundle.contracts.map { |c| { signer_id: recipient_signer.id, contract_id: c.id, created_at: now, updated_at: now } },
      unique_by: [ :signer_id, :contract_id ]
    )
  end

  def recompute_bundle_superseded_state
    bundle&.recompute_superseded_state_if_rules_changed
  end

  def portal_instance_reference_must_exist
    return if portal_instance_uuid.blank? || portal_instance.present?

    errors.add(:portal_instance, "must exist")
  end

  def portal_instance_must_be_verified
    return if portal_instance.verified?

    errors.add(:portal_instance, "must be verified")
  end

  def portal_instance_matches_federation_mode
    if portal_instance_id.present? && federation_mode != "federated"
      errors.add(:federation_mode, "must be federated when portal instance is set")
    elsif portal_instance_id.blank? && federation_mode == "federated"
      errors.add(:portal_instance, "must be present for federated recipients")
    end
  end

  def federated_recipient_cannot_have_local_user
    return unless federation_mode == "federated" && user.present?

    errors.add(:user, "must be blank for federated recipients")
  end
end
