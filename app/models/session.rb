# == Schema Information
#
# Table name: sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  error_message      :text
#  options            :jsonb
#  signing_started_at :datetime
#  status             :integer          default("pending"), not null
#  type               :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  signer_contract_id :bigint           not null
#
# Indexes
#
#  index_sessions_on_signer_contract_id  (signer_contract_id)
#  index_sessions_on_type                (type)
#
# Foreign Keys
#
#  fk_rails_...  (signer_contract_id => signer_contracts.id)
#
class Session < ApplicationRecord
  belongs_to :signer_contract

  delegate :contract, to: :signer_contract
  delegate :signer,   to: :signer_contract

  encrypts :options

  enum :status, {
    pending: 0,
    signed: 1,
    failed: 2,
    expired: 3,
    canceled: 4
  }

  validates :signing_started_at, presence: true

  scope :recent, -> { order(created_at: :desc) }

  after_update_commit :handle_status_change, if: :saved_change_to_status?

  def recipient
    signer_contract.recipient
  end

  def iframe_param
    options&.dig("iframe").presence
  end

  def bundle_contracts_total
    contract.bundle&.contracts&.count.to_i
  end

  def remaining_bundle_contracts_count
    bundle = contract.bundle
    return 0 unless bundle

    if recipient
      recipient.signer_contracts.awaiting.where(contract: bundle.contracts).count
    else
      bundle.contracts.to_a.count(&:awaiting_signature?)
    end
  end

  def bundle_signing_complete?
    contract.bundle.present? && remaining_bundle_contracts_count.zero?
  end

  def inline_bundle_success?
    contract.bundle.present? && bundle_contracts_total > 1 && !bundle_signing_complete?
  end

  def close_iframe_after_completion?
    return false unless iframe_param.present?
    return true unless contract.bundle.present?

    bundle_signing_complete?
  end

  def completion_event_payload
    {
      type: "agp-custom-event",
      status: "document-signed",
      contract_id: contract.uuid,
      bundle_id: contract.bundle&.uuid,
      total_contracts_count: bundle_contracts_total,
      remaining_contracts_count: remaining_bundle_contracts_count,
      bundle_completed: bundle_signing_complete?,
      close_iframe: close_iframe_after_completion?
    }
  end

  def not_pending?
    !pending?
  end

  def eidentita?
    is_a?(EidentitaSession)
  end

  def avm?
    is_a?(AvmSession)
  end

  def autogram?
    is_a?(AutogramSession)
  end

  def mark_failed!(message = nil)
    failed!
    update!(error_message: message || "Signing failed")
  end

  def accept_signed_file(signed_file)
    decoded_signed_file = decode_signed_file!(signed_file)
    validate_signed_file!(decoded_signed_file)

    ActiveRecord::Base.transaction do
      new_filename = generate_signed_filename
      new_content_type = new_filename.ends_with?(".asice") ? "application/vnd.etsi.asic-e+zip" : "application/pdf"
      contract.signed_document.purge if contract.signed_document.attached?
      contract.signed_document.attach(
        io: StringIO.new(decoded_signed_file),
        filename: new_filename,
        content_type: new_content_type
      )
      save!
    end

    signed!
    contract.sessions.pending.where.not(id: id).each(&:canceled!)
  end

  def generate_signed_filename
    if contract.documents.count == 1
      original_filename = contract.documents.first.blob.filename.base
      return "#{original_filename}-signed.#{contract.signature_parameters.container.present? ? 'asice' : 'pdf'}"
    end

    "contract-#{id}-signed.#{contract.signature_parameters.container.present? ? 'asice' : 'pdf'}"
  end

  def decode_signed_file!(signed_file)
    decoded_signed_file = Base64.strict_decode64(signed_file.to_s)
    raise "Signed document payload is empty" if decoded_signed_file.blank?

    decoded_signed_file
  rescue ArgumentError
    raise "Signed document payload is not valid Base64"
  end

  def validate_signed_file!(decoded_signed_file)
    validation_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(decoded_signed_file),
      filename: generate_signed_filename,
      content_type: inferred_signed_content_type
    )

    validation_document = Document.new(blob: validation_blob)
    validation_result = AutogramEnvironment.autogram_service.validate_signatures(validation_document)

    raise "Signed document validation failed" unless validation_result.valid_response?
    raise "Signed document does not contain signatures" unless validation_result.has_signatures
    raise "Signed document signatures are invalid" unless validation_result.signatures.any? { |signature| signature[:valid] }

    ensure_signed_content_matches_contract!(validation_result)
  ensure
    validation_blob&.purge
  end

  def ensure_signed_content_matches_contract!(validation_result)
    return unless contract.signature_parameters.container.present?

    expected_documents = contract.documents.count
    signed_objects = validation_result.document_info[:signed_objects_count].to_i

    return if expected_documents.zero?
    return if signed_objects >= expected_documents

    raise "Signed document does not include all contract documents"

    # TODO: compare old and new versions of the signed document via external service - AutogramEnvironment.autogram_service.compare_documents(old: contract.documents.map(&:blob), new: validation_blob) - doesnt exist yet
  end

  def inferred_signed_content_type
    contract.signature_parameters.container.present? ? "application/vnd.etsi.asic-e+zip" : "application/pdf"
  end

  def handle_status_change
    mark_signer_contract_signed if signed?
    touch(:completed_at) unless pending?
    broadcast_status_change
  end

  def mark_signer_contract_signed
    signer_contract.update_column(:signed_at, completed_at || Time.current)
  end

  def broadcast_status_change
    case status
    when "failed"
      broadcast_signing_error(error_message || "Signing failed")
    when "expired"
      broadcast_signing_error("Signing expired")
    when "signed"
      contract.notify_signed!(signer: signer)
      Turbo::StreamsChannel.broadcast_replace_to(
        self,
        target: "signature_apps_#{contract.uuid}",
        partial: "contracts/sessions/signed",
        locals: { session: self }
      )
    when "canceled"
      Turbo::StreamsChannel.broadcast_action_to(self, action: :refresh)
    end
  end

  def broadcast_signing_error(error_message)
    Turbo::StreamsChannel.broadcast_replace_to(
      self,
      target: "signature_apps_#{contract.uuid}",
      partial: "contracts/sessions/error",
      locals: { session: self }
    )
  end
end
