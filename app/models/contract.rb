# == Schema Information
#
# Table name: contracts
#
#  id              :bigint           not null, primary key
#  allowed_methods :string           default([]), is an Array
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

  has_one :signature_parameters, class_name: "Ades::SignatureParameters", dependent: :destroy, required: true
  has_many :documents, dependent: :destroy
  has_many :avm_sessions, dependent: :destroy
  has_one_attached :signed_document

  accepts_nested_attributes_for :documents, allow_destroy: true, reject_if: proc { |attributes| attributes["blob"].blank? }
  accepts_nested_attributes_for :signature_parameters

  # ALLOWED_METHODS = %w[qes ts-qes cts-qes ades ses click scan notary paper].freeze
  ALLOWED_METHODS = %w[qes ts-qes].freeze

  validate :validate_allowed_methods
  validates :signature_parameters, presence: true, if: -> { allowed_methods.present? && (allowed_methods & %w[qes qes-ts cts-qes ades]).any? }
  validate :validate_documents
  validate :validate_signature_parameters, if: -> { signature_parameters.present? }
  validates :uuid, presence: true, uniqueness: true

  before_validation :ensure_uuid, on: :create

  # Use UUID in URLs instead of ID for security
  def to_param
    uuid
  end

  def self.new_from_ui(parameters)
    contract = new(parameters)
    contract.uuid ||= SecureRandom.uuid
    contract.allowed_methods = %w[qes ts-qes] unless contract.allowed_methods.present?
    contract
  end

  def accept_signed_file(signed_file)
    # Check if signed_file is a signed version of the original documents
    # AutogramEnvironment.autogram_service.validate_signed_file(signed_file, documents.map(&:blob))

    # Validate the signatures in the signed file
    # AutogramEnvironment.autogram_service.validate_signatures(signed_file, signature_parameters)

    # If validation passes, attach the signed document
    Rails.logger.info "Attaching signed document..."
    signed_document.attach(
      io: StringIO.new(Base64.decode64(signed_file)),
      filename: generate_signed_filename,
      content_type: generate_signed_conentent_type
    )
    save!
    Rails.logger.info "Signed document attached successfully."

    # Mark any active AVM sessions as completed
    avm_sessions.active.each(&:mark_completed!)

    # Broadcast signing success for any signing method
    broadcast_signing_success
  end

  def awaiting_signature?
    signed_document.blank?
  end

  def current_avm_session
    avm_sessions.active.recent.first
  end

  def has_active_avm_session?
    current_avm_session.present? && !current_avm_session.expired?
  end

  def broadcast_signing_success
    Turbo::StreamsChannel.broadcast_replace_to(
      "contract_#{uuid}",
      target: "signature_actions_#{uuid}",
      partial: "contracts/signature_actions",
      locals: { contract: self }
    )

    # Also broadcast a success message
    Turbo::StreamsChannel.broadcast_prepend_to(
      "contract_#{uuid}",
      target: "flash_messages",
      partial: "shared/flash_message",
      locals: {
        message: "Contract signed successfully.",
        type: "notice"
      }
    )

    Rails.logger.info "Broadcasted signing success for contract #{uuid}."
    bundle.contract_signed(self) if bundle.present?
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def generate_signed_filename
    if documents.count == 1
      original_filename = documents.first.blob.filename.base
      return "#{original_filename}-signed.#{signature_parameters.container.present? ? 'asice' : 'pdf'}"
    end

    "contract-#{id}-signed.#{signature_parameters.container.present? ? '.asice' : 'pdf'}"
  end

  def generate_signed_conentent_type
    if signature_parameters.container.present?
      "application/vnd.etsi.asic-e+zip"
    else
      "application/pdf"
    end
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
end
