# == Schema Information
#
# Table name: contracts
#
#  id              :bigint           not null, primary key
#  allowed_methods :string           default(["qes"]), is an Array
#  uuid            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  bundle_id       :bigint
#  user_id         :bigint
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
  belongs_to :user, optional: true
  belongs_to :bundle, optional: true

  has_many :signer_contracts, dependent: :destroy
  has_many :signers, through: :signer_contracts
  has_many :recipients, through: :signers
  has_one :signature_parameters, class_name: "Ades::SignatureParameters", dependent: :destroy, required: true
  has_many :documents, dependent: :destroy
  has_many :sessions, through: :signer_contracts
  has_one_attached :signed_document

  accepts_nested_attributes_for :documents, allow_destroy: true, reject_if: proc { |attributes| attributes["blob"].blank? }
  accepts_nested_attributes_for :signature_parameters

  ALLOWED_METHODS = ENV.fetch("ALLOWED_METHODS", "qes").split(",").map(&:strip)
  attribute :allowed_methods, default: [ "qes" ]

  validate :validate_allowed_methods
  validates :signature_parameters, presence: true, if: -> { allowed_methods.present? && allowed_methods.include?("qes") }
  validate :validate_documents
  validate :validate_signature_parameters, if: -> { signature_parameters.present? }
  validates :uuid, presence: true, uniqueness: true
  validates_associated :signature_parameters

  before_validation :ensure_uuid, on: :create
  before_validation :initialize_signature_parameters
  after_create :associate_with_bundle_recipients

  scope :anonymous, -> { where(user_id: nil) }
  scope :awaiting_signature_for, ->(user) {
    joins(signer_contracts: { signer: :recipient })
      .where(signer_contracts: { signed_at: nil })
      .where(signers: { type: "RecipientSigner" })
      .where(recipients: { user_id: user.id, status: :pending })
      .distinct
  }

  def to_param
    uuid
  end

  def available_signature_methods
    ALLOWED_METHODS
  end

  def notify_signed!(signer: nil)
    Notification::ContractSignedJob.perform_later(self, signer: signer) if should_notify_user?(signer: signer)

    bundle.notify_contract_signed(self, signer) if bundle.present?

    Turbo::StreamsChannel.broadcast_action_to(self, action: :refresh)
  end

  def documents_to_sign
    return documents unless signed_document.attached?

    [ Document.new(blob: signed_document.blob) ]
  end

  def awaiting_signature?
    signed_document.blank? || bundle&.awaiting_recipients?(contract: self)
  end

  def extendable_signatures?
    return Document.new(blob: signed_document.blob).extendable_signatures? if signed_document.attached?

    return false unless documents.count == 1
    documents.first.extendable_signatures?
  end

  def extend_signatures!
    return unless extendable_signatures?

    if signed_document.attached?
      document = Document.new(blob: signed_document.blob)
      document.extend_signatures!
      signed_document.purge
      signed_document.attach(
        io: StringIO.new(document.content),
        filename: document.filename,
        content_type: document.content_type
      )
      save!
    else
      documents.first.extend_signatures!
    end
  end

  def current_avm_session
    sessions.where(type: "AvmSession", status: :pending)
            .order(created_at: :desc).first
  end

  def has_active_avm_session?
    current_avm_session.present? && !current_avm_session.expired?
  end

  def current_eidentita_session
    sessions.where(type: "EidentitaSession", status: :pending)
            .order(created_at: :desc).first
  end

  def has_active_eidentita_session?
    current_eidentita_session.present?
  end

  def current_autogram_session
    sessions.where(type: "AutogramSession", status: :pending)
            .order(created_at: :desc).first
  end

  def has_active_autogram_session?
    current_autogram_session.present?
  end

  def should_notify_user?(signer: nil)
    user.present? && bundle.nil? && !awaiting_signature? && user != signer&.user
  end

  def short_uuid
    uuid.first(8)
  end

  def display_name
    documents.first.blob.filename
  end

  def validation_result
    document_to_validate = if signed_document.attached?
      Document.new(blob: signed_document.blob)
    elsif documents.size == 1
      documents.first
    else
      nil
    end

    document_to_validate&.validation_result
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def validate_allowed_methods
    return errors.add(:allowed_methods, "can't be blank") if allowed_methods.blank?

    invalid_methods = allowed_methods - ALLOWED_METHODS
    errors.add(:allowed_methods, "contains invalid values: #{invalid_methods.join(', ')}") if invalid_methods.any?
  end

  def validate_documents
    if documents.empty?
      errors.add(:documents, "must have at least one document")
    end
  end

  def validate_signature_parameters
    signature_parameters.validate(errors)
  end

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def initialize_signature_parameters
    build_signature_parameters unless signature_parameters
  end

  def associate_with_bundle_recipients
    return unless bundle.present? && bundle.recipients.any?

    now = Time.current
    inserts = bundle.recipients.map do |recipient|
      recipient_signer = RecipientSigner.create_or_find_by!(recipient: recipient)
      { signer_id: recipient_signer.id, contract_id: id, created_at: now, updated_at: now }
    end
    SignerContract.insert_all(inserts, unique_by: [ :signer_id, :contract_id ])
  end
end
