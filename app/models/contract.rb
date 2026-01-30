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

  has_and_belongs_to_many :recipients
  has_one :signature_parameters, class_name: "Ades::SignatureParameters", dependent: :destroy, required: true
  has_many :documents, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_one_attached :signed_document

  accepts_nested_attributes_for :documents, allow_destroy: true, reject_if: proc { |attributes| attributes["blob"].blank? }
  accepts_nested_attributes_for :signature_parameters

  # ALLOWED_METHODS = %w[qes ts-qes cts-qes ades ses click scan notary paper].freeze
  ALLOWED_METHODS = %w[qes ts-qes].freeze
  attribute :allowed_methods, default: [ "qes" ]

  validate :validate_allowed_methods
  validates :signature_parameters, presence: true, if: -> { allowed_methods.present? && (allowed_methods & %w[qes qes-ts cts-qes ades]).any? }
  validate :validate_documents
  validate :validate_signature_parameters, if: -> { signature_parameters.present? }
  validates :uuid, presence: true, uniqueness: true
  validates_associated :signature_parameters

  before_validation :ensure_uuid, on: :create
  before_validation :initialize_signature_parameters
  before_validation :set_signature_level_for_ts_qes
  after_create :associate_with_bundle_recipients

  def to_param
    uuid
  end

  def notify_signed!(recipient: nil, signer: nil)
    Notification::ContractSignedJob.perform_later(self) unless should_notify_user?(signer: signer)

    bundle.notify_contract_signed(self, recipient) if bundle.present?

    Turbo::StreamsChannel.broadcast_action_to(
      "contract_#{uuid}",
      action: :refresh
    )
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
    # TODO: Improve logic to not notify "self sign" by user
    user.present? && bundle.nil? && !awaiting_signature? && user != signer
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

  # Custom setter to convert singular allowed_method to plural allowed_methods array
  def allowed_method=(method)
    self.allowed_methods = [ method ].compact
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

  def set_signature_level_for_ts_qes
    return unless allowed_methods.present?
    return unless signature_parameters.present?

    if allowed_methods.include?("ts-qes")
      signature_parameters.level = "BASELINE_T"
    elsif allowed_methods.include?("qes") && allowed_methods.exclude?("ts-qes")
      signature_parameters.level = "BASELINE_B"
    end
  end

  def initialize_signature_parameters
    return if signature_parameters.present?

    self.signature_parameters = Ades::SignatureParameters.new(
      level: allowed_methods.include?("ts-qes") ? "BASELINE_T" : "BASELINE_B",
      format: "CAdES",
      container: "ASiC_E"
    )
  end

  def associate_with_bundle_recipients
    self.recipients = bundle.recipients if bundle.present?
  end
end
