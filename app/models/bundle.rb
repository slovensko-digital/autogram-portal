# == Schema Information
#
# Table name: bundles
#
#  id                  :bigint           not null, primary key
#  note                :text
#  publicly_visible    :boolean          default(FALSE), not null
#  required_signatures :integer
#  signing_rule        :string           default("all"), not null
#  uuid                :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  user_id             :bigint           not null
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
  validates :signing_rule, inclusion: { in: %w[all any threshold] }
  validates :required_signatures, presence: true,
                                  numericality: { only_integer: true, greater_than: 0 },
                                  if: -> { signing_rule == "threshold" }

  after_create :notify_recipients
  after_save :recompute_superseded_state_if_rules_changed, if: :rules_changed?

  scope :publicly_visible, -> { where(publicly_visible: true) }
  scope :recipient_user, ->(user) { joins(:recipients).where.not(author: user).where(recipients: { user: user }) }

  def to_param
    uuid
  end

  def display_name
    "#{I18n.t('bundles.display_name')} #{short_uuid}"
  end

  def completed?
      return threshold_met? && !awaiting_recipients? if recipients.exists?

     contracts.where.missing(:signed_document_attachment).none?
  end

  def bundle_state
    return :no_recipients unless recipients.exists?
    return :completed if completed?
    return :declined if declined_recipients?
    :awaiting
  end

  def awaiting_recipients?(contract: nil)
    scope = recipients
      .joins(recipient_signer: :signer_contracts)
      .where(signer_contracts: { signed_at: nil, declined_at: nil, superseded_at: nil })
    scope = scope.where(signer_contracts: { contract_id: contract.id }) if contract
    scope.exists?
  end

  def completed_recipients
    not_completed_ids = recipients
      .joins(recipient_signer: :signer_contracts)
      .where("signer_contracts.signed_at IS NULL OR signer_contracts.declined_at IS NOT NULL")
      .select(:id)
    recipients.where.not(id: not_completed_ids)
  end

  def notify_contract_signed(contract, signer)
    Notification::BundleContractSignedJob.perform_later(self, contract, signer: signer)

    supersede_pending_recipients! if threshold_met? && !completed?

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

  # Returns true when the signing rule is satisfied by the current number of fully-signed recipients.
  def threshold_met?
    case signing_rule
    when "any"
      signed_recipients_count >= 1
    when "threshold"
      signed_recipients_count >= required_signatures.to_i
    else # "all"
      signed_recipients_count >= recipients.count
    end
  end

  # Number of recipients who have signed every contract in the bundle.
  def signed_recipients_count
    not_signed_ids = recipients
      .joins(recipient_signer: :signer_contracts)
      .where("signer_contracts.signed_at IS NULL")
      .select(:id)
    recipients.where.not(id: not_signed_ids).count
  end

  # Mark every still-awaiting signer_contract in this bundle as superseded, then
  # notify the affected recipients that their signature is no longer required.
  def supersede_pending_recipients!
    with_lock do
      awaiting_sc_ids = SignerContract
        .joins(signer: :recipient)
        .where(recipients: { bundle_id: id }, signed_at: nil, declined_at: nil, superseded_at: nil)
        .pluck(:id)

      return if awaiting_sc_ids.empty?

      now = Time.current
      SignerContract.where(id: awaiting_sc_ids).update_all(superseded_at: now, updated_at: now)

      affected_recipient_ids = SignerContract
        .joins(signer: :recipient)
        .where(id: awaiting_sc_ids)
        .pluck("recipients.id")
        .uniq

      Recipient.where(id: affected_recipient_ids).find_each do |recipient|
        Notification::RecipientNoLongerRequiredJob.perform_later(recipient)
      end
    end
  end

  # Recompute superseded state when signing rule or threshold changes.
  # If the threshold increases or changes, un-supersede recipients who no longer need to be superseded.
  # If the threshold was previously met but now isn't, un-supersede all recipients.
  def recompute_superseded_state_if_rules_changed
    with_lock do
      # Find all currently superseded signer contracts
      superseded_scs = SignerContract
        .joins(signer: :recipient)
        .where(recipients: { bundle_id: id }, superseded_at: nil..Float::INFINITY)

      return if superseded_scs.empty?

      # Check if the threshold is no longer met with new rules
      # If so, un-supersede all pending signatures
      if !threshold_met?
        # Clear superseded status for all contracts in this bundle
        now = Time.current
        superseded_scs.update_all(superseded_at: nil, updated_at: now)
        return
      end

      # If threshold is still met, check if any superseded recipients' signatures would
      # now contribute to the threshold (in case required_signatures decreased)
      # For "threshold" and "all" modes, we might need to un-supersede if the rule is looser
      # For now, we keep them superseded since threshold is still met
      # Future enhancement: Could re-evaluate on case-by-case basis if needed
    end
  end

  private

  def rules_changed?
    will_save_change_to_signing_rule? || will_save_change_to_required_signatures?
  end

  def declined_recipients?
    recipients
      .joins(recipient_signer: :signer_contracts)
      .where.not(signer_contracts: { declined_at: nil })
      .exists?
  end

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
