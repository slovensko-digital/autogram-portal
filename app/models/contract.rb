# == Schema Information
#
# Table name: contracts
#
#  id                           :bigint           not null, primary key
#  allowed_methods              :string           default(["qes"]), is an Array
#  author_notifications_enabled :boolean          default(FALSE), not null
#  temporary_storage_reason     :string
#  uuid                         :string           not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  bundle_id                    :bigint
#  user_id                      :bigint
#
# Indexes
#
#  index_contracts_on_bundle_id                 (bundle_id)
#  index_contracts_on_temporary_storage_reason  (temporary_storage_reason)
#  index_contracts_on_user_id                   (user_id)
#  index_contracts_on_uuid                      (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (user_id => users.id)
#
class Contract < ApplicationRecord
  ValidationEntry = Struct.new(:label, :validation_result, :document_hash, keyword_init: true)
  PREPARED_SIGNATURE_FIELDS_ORIGIN = "prepared_signature_fields".freeze
  NON_FINALIZED_CONTENT_VERSION_ORIGINS = [ PREPARED_SIGNATURE_FIELDS_ORIGIN ].freeze
  MissingSignedDocument = Struct.new(:contract) do
    def attached?
      false
    end

    def blank?
      true
    end

    def present?
      false
    end
  end

  belongs_to :user, optional: true
  belongs_to :bundle, optional: true

  has_many :signer_contracts, dependent: :destroy
  has_many :signers, through: :signer_contracts
  has_many :recipients, through: :signers
  has_many :content_versions, -> { order(version_number: :desc, id: :desc) }, class_name: "ContractContentVersion", dependent: :destroy
  has_many :contract_validation_records, dependent: :nullify
  has_one :signature_parameters, class_name: "Ades::SignatureParameters", dependent: :destroy, required: true
  has_many :documents, dependent: :destroy
  has_many :signature_field_preparations, dependent: :destroy
  has_many :sessions, through: :signer_contracts

  accepts_nested_attributes_for :documents, allow_destroy: true, reject_if: proc { |attributes| attributes["blob"].blank? }
  accepts_nested_attributes_for :signature_parameters

  ALLOWED_METHODS = ENV.fetch("ALLOWED_METHODS", "qes,ades").split(",").map(&:strip)
  attribute :allowed_methods, default: [ "qes" ]

  validate :validate_allowed_methods
  validates :signature_parameters, presence: true, if: -> { allowed_methods.present? && allowed_methods.include?("qes") }
  validate :validate_documents
  validate :validate_signature_parameters, if: -> { signature_parameters.present? }
  validates :uuid, presence: true, uniqueness: true
  validates_associated :signature_parameters

  before_validation :ensure_uuid, on: :create
  before_validation :expand_asice_container_documents, on: :create
  before_validation :initialize_signature_parameters
  after_create :associate_with_bundle_recipients
  after_commit :schedule_existing_signed_content_capture, on: :create

  scope :anonymous, -> { where(user_id: nil).where(bundle_id: nil) }
  scope :awaiting_signature_for, ->(user) {
    joins(signer_contracts: { signer: :recipient })
      .where(signer_contracts: { signed_at: nil, declined_at: nil })
      .where(signers: { type: "RecipientSigner" })
      .where(recipients: { user_id: user.id, withdrawn_at: nil })
      .distinct
    }
  scope :standalone, -> { where(bundle_id: nil) }

  def to_param
    uuid
  end

  def available_signature_methods
    ALLOWED_METHODS
  end

  def available_signature_methods_for(next_step:, signature_format: signature_parameters&.format)
    available_signature_methods.dup
  end

  def notify_signed!(signer: nil)
    Notification::ContractSignedJob.perform_later(self, signer: signer) if should_notify_user?(signer: signer)

    bundle.notify_contract_signed(self, signer) if bundle.present?

    Turbo::StreamsChannel.broadcast_action_to(self, action: :refresh)
  end

  def latest_content_version
    if association(:content_versions).loaded?
      content_versions.max_by { |version| [ version.version_number.to_i, version.id.to_i ] }
    else
      content_versions.first
    end
  end

  def signed_document_versions
    association(:content_versions).loaded? ? content_versions.sort_by { |version| [ -version.version_number.to_i, -version.id.to_i ] } : content_versions
  end

  def latest_source_content_version
    latest_content_version
  end

  def latest_finalized_content_version
    version = latest_source_content_version
    return if version.blank? || NON_FINALIZED_CONTENT_VERSION_ORIGINS.include?(version.origin)

    version
  end

  def signed_document
    latest_finalized_content_version&.file || MissingSignedDocument.new(self)
  end

  def signed_document_attached?
    latest_finalized_content_version&.file&.attached? || false
  end

  def private_signature_evidence_records
    SignatureEvidenceRecord
      .where(session_id: sessions.select(:id))
      .with_attached_private_evidence_package
      .order(created_at: :desc)
      .select { |record| record.private_evidence_package.attached? }
  end

  def source_document_attached?
    latest_source_content_version&.file&.attached? || false
  end

  def prepared_signature_fields_source_attached?
    latest_prepared_signature_fields_content_version&.file&.attached? || false
  end

  def add_signed_content_version!(content:, filename:, content_type:, origin:, created_at: Time.current)
    raise "Contract must be persisted before adding signed content versions" unless persisted?

    version = content_versions.build(
      version_number: next_content_version_number,
      origin: origin,
      created_at: created_at,
      updated_at: created_at
    )
    version.file.attach(
      io: StringIO.new(content),
      filename: filename,
      content_type: content_type
    )
    version.save!
    version
  end

  def documents_to_sign
    return documents unless source_document_attached?

    [ latest_source_content_version.document ]
  end

  def signature_validation_results
    if source_document_attached?
      [ latest_source_content_version&.validation_result ]
    else
      documents.order(:id).map(&:validation_result)
    end.compact
  end

  def has_cryptographic_signatures?
    signature_validation_results.any?(&:has_signatures?)
  rescue StandardError
    false
  end

  def pades_signed?
    signature_validation_results.any? do |validation_result|
      validation_result.has_signatures? && validation_result.documentInfo[:signatureForm] == "PAdES"
    end
  rescue StandardError
    false
  end

  def pades_field_preparation_allowed?
    bundle.present? && documents.one? && documents.first.is_pdf? && signature_parameters&.format == "PAdES" && !has_cryptographic_signatures? && allowed_methods.include?("qes")
  end

  def pades_field_preparation_allowed_for?(user)
    pades_field_preparation_allowed? && bundle&.author == user
  end

  def prepared_signature_field_preparation_for(recipient:)
    return if recipient.blank? || !prepared_signature_fields_source_attached?

    signature_field_preparations.find_by(recipient: recipient, document: documents.first)
  end

  def prepared_signature_field_appearance_required_for?(recipient: nil, signer_contract: nil)
    recipient ||= signer_contract&.recipient
    preparation = prepared_signature_field_preparation_for(recipient: recipient)
    return false if preparation.blank?

    signer_contract ||= recipient&.recipient_signer&.signer_contracts&.find_by(contract: self)
    return true if signer_contract.blank?

    signer_contract.latest_signature_field_appearance_for(preparation.document).blank?
  end

  def visual_signing_allowed?
    !pades_signed?
  end

  def latest_visual_signature_stamps
    VisualStamp.joins(:signer_contract)
               .where(signer_contracts: { contract_id: id }, purpose: VisualStamp.purposes[:visual_method])
               .includes(signer_contract: :signer, image_attachment: :blob)
               .order(created_at: :desc)
  end

  def documents_to_sign_for(signer_contract: nil)
    source_documents = documents_to_sign
    return source_documents unless signer_contract && source_documents.one? && !source_document_attached?

    prepared_stamp = signer_contract.latest_qes_visual_stamp_for(documents.first)
    return source_documents unless prepared_stamp&.file&.attached?

    [ prepared_stamp.stamped_document ]
  end

  def awaiting_signature?
    !signed_document_attached? || bundle&.awaiting_recipients?(contract: self)
  end

  def visual_signed?
    signed_document_attached? && latest_finalized_content_version&.origin == "visual"
  end

  def extendable_signatures?(target_level: "T")
    return latest_content_version.extendable_signatures?(target_level: target_level) if signed_document_attached?

    return false unless documents.count == 1
    documents.first.extendable_signatures?(target_level: target_level)
  end

  def available_extension_target_levels
    return latest_content_version.available_extension_target_levels if signed_document_attached?

    return [] unless documents.count == 1
    documents.first.available_extension_target_levels
  end

  def extend_signatures!(target_level: "T", source_content_version: latest_content_version)
    return unless extendable_signatures?(target_level: target_level)

    source_document = source_content_version&.document || documents.first
    raise "No signed content is available for extension" if source_document.blank?

    extended_content = AutogramEnvironment.autogram_service.extend_signatures(source_document, target_level: target_level)
    version = add_signed_content_version!(
      content: extended_content,
      filename: source_document.filename,
      content_type: source_document.content_type,
      origin: "extension"
    )
    persist_validation_record!(contract_content_version: version)
    version
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
    return false unless author_notifications_enabled?

    user.present? && bundle.nil? && !awaiting_signature? && user != signer&.user
  end

  def short_uuid
    uuid.first(8)
  end

  def display_name
    documents.first.blob.filename
  end

  def validation_result
    validation_results.first&.validation_result
  end

  def validation_results
    if source_document_attached?
      content_version = latest_source_content_version
      [ ValidationEntry.new(
          label: content_version.filename.to_s,
          validation_result: content_version.validation_result,
          document_hash: Digest::SHA256.hexdigest(content_version.content)
        ) ]
    else
      documents.order(:id).map do |document|
        ValidationEntry.new(
          label: document.filename.to_s,
          validation_result: document.validation_result,
          document_hash: Digest::SHA256.hexdigest(document.content)
        )
      end
    end
  end

  def replace_prepared_signature_field_content_versions!
    content_versions.where(origin: PREPARED_SIGNATURE_FIELDS_ORIGIN).destroy_all
  end

  def add_prepared_signature_fields_content_version!(content:, filename:, content_type:, created_at: Time.current)
    replace_prepared_signature_field_content_versions!
    add_signed_content_version!(
      content: content,
      filename: filename,
      content_type: content_type,
      origin: PREPARED_SIGNATURE_FIELDS_ORIGIN,
      created_at: created_at
    )
  end

  def persist_validation_record!(contract_content_version: latest_content_version, validation_result: nil, signed_content: nil, filename: nil, session: nil)
    owner = user || bundle&.author
    return if owner.blank? || !owner.archivation_enabled?
    # return if contract_content_version.blank?

    signed_content ||= contract_content_version.content
    filename ||= contract_content_version.filename
    validation_result ||= contract_content_version.validation_result(skip_cache: true)

    # return if signed_content.blank? || filename.blank?
    # return if validation_result.blank? || !validation_result.valid_response? || !validation_result.has_signatures?

    ContractValidationRecord.capture!(
      contract: self,
      contract_content_version: contract_content_version,
      validation_result: validation_result,
      signed_content: signed_content,
      filename: filename,
      session: session
    )
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

  def latest_prepared_signature_fields_content_version
    if association(:content_versions).loaded?
      content_versions
        .select { |version| version.origin == PREPARED_SIGNATURE_FIELDS_ORIGIN }
        .max_by { |version| [ version.version_number.to_i, version.id.to_i ] }
    else
      content_versions.where(origin: PREPARED_SIGNATURE_FIELDS_ORIGIN).first
    end
  end

  def expand_asice_container_documents
    return if signed_document_attached?
    return unless documents.one?

    container_document = documents.first
    return unless container_document&.blob&.attached?
    return unless container_document.is_asice?

    extractor = AsiceContainerExtractor.new(container_document)
    extracted_documents = extractor.extract_documents
    return if extracted_documents.blank?

    self.documents = extracted_documents.map do |extracted_document|
      Document.new(blob: extracted_document.blob).tap do |document|
        document.build_xdc_parameters if extracted_document.xdcf
      end
    end
    build_signed_content_version(
      content: extractor.container_content,
      filename: container_document.filename,
      content_type: container_document.content_type,
      origin: "uploaded_signed"
    )
  end

  def next_content_version_number
    versions = if association(:content_versions).loaded?
      content_versions.map(&:version_number)
    else
      content_versions.pluck(:version_number)
    end

    versions.compact.max.to_i + 1
  end

  def build_signed_content_version(content:, filename:, content_type:, origin:, created_at: Time.current)
    content_versions.build(
      version_number: next_content_version_number,
      origin: origin,
      created_at: created_at,
      updated_at: created_at
    ).tap do |version|
      version.file.attach(
        io: StringIO.new(content),
        filename: filename,
        content_type: content_type
      )
    end
  end

  def capture_existing_signed_content!
    if latest_content_version.present?
      persist_validation_record!
      return
    end

    return unless documents.one?

    document = documents.first
    validation_result = document.validation_result(skip_cache: true)
    return unless validation_result.valid_response?
    return unless validation_result.has_signatures?

    version = add_signed_content_version!(
      content: document.content,
      filename: document.filename,
      content_type: document.content_type,
      origin: "uploaded_signed"
    )
    persist_validation_record!(
      contract_content_version: version,
      validation_result: validation_result,
      signed_content: document.content,
      filename: document.filename
    )
  end

  def schedule_existing_signed_content_capture
    owner = user || bundle&.author
    return if owner.blank? || !owner.archivation_enabled?
    return unless latest_content_version.present? || documents.one?

    ContractValidationRecordCaptureJob.perform_later(id)
  end

  def associate_with_bundle_recipients
    return unless bundle.present? && bundle.active_recipients.any?

    now = Time.current
    inserts = bundle.active_recipients.map do |recipient|
      recipient_signer = recipient.recipient_signer || recipient.create_recipient_signer!
      { signer_id: recipient_signer.id, contract_id: id, created_at: now, updated_at: now }
    end
    SignerContract.insert_all(inserts, unique_by: [ :signer_id, :contract_id ])
  end
end
