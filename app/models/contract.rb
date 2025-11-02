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
  before_validation :set_signature_level_for_ts_qes

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
    # TODO: Check if signed_file is a signed version of the original documents
    # AutogramEnvironment.autogram_service.validate_signed_file(signed_file, documents.map(&:blob))

    # TODO: Validate the signatures in the signed file
    # AutogramEnvironment.autogram_service.validate_signatures(signed_file, signature_parameters)

    signed_document.attach(
      io: StringIO.new(Base64.decode64(signed_file)),
      filename: generate_signed_filename,
      content_type: generate_signed_conentent_type
    )
    save!

    avm_sessions.active.each(&:mark_completed!)
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

    Turbo::StreamsChannel.broadcast_prepend_to(
      "contract_#{uuid}",
      target: "flash_messages",
      partial: "shared/flash_message",
      locals: {
        message: "Contract signed successfully.",
        type: "notice"
      }
    )

    bundle.contract_signed(self) if bundle.present?
  end

  def short_uuid
    uuid.first(8)
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

  def set_signature_level_for_ts_qes
    return unless allowed_methods.present?
    return unless signature_parameters.present?

    if allowed_methods.include?("ts-qes")
      signature_parameters.level = "BASELINE_T"
    elsif allowed_methods.include?("qes") && allowed_methods.exclude?("ts-qes")
      signature_parameters.level = "BASELINE_B"
    end
  end
end
