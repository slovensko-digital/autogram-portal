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

  def podpisuj?
    is_a?(PodpisujSession)
  end

  def ades_evidence?
    is_a?(AdesEvidenceSession)
  end

  def self.old_card?(qscd)
    return false unless qscd.present?

    [ :eid_2013, :dpb_2014 ].include?(qscd.to_sym)
  end

  def self.multiple_files?(contract)
    contract.documents.count > 1
  end

  def self.available?(qscd, contract)
    raise NotImplementedError, "Subclasses must implement the .available?(qscd, contract) method"
  end

  def mark_failed!(message = nil)
    failed!
    update!(error_message: message || "Signing failed")
  end

  def accept_signed_file(signed_file)
    decoded_signed_file = decode_signed_file!(signed_file)
    validation_result = validate_signed_file!(decoded_signed_file)

    ActiveRecord::Base.transaction do
      new_filename = generate_signed_filename
      new_content_type = new_filename.ends_with?(".asice") ? "application/vnd.etsi.asic-e+zip" : "application/pdf"
      version = contract.add_signed_content_version!(
        content: decoded_signed_file,
        filename: new_filename,
        content_type: new_content_type,
        origin: "signing"
      )
      contract.persist_validation_record!(
        contract_content_version: version,
        validation_result: validation_result,
        signed_content: decoded_signed_file,
        filename: new_filename,
        session: self
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
    raise "Signed document does not contain signatures" unless validation_result.has_signatures?
    raise "Signed document signatures are invalid" unless validation_result.signatures.any? { |signature| signature.valid }

    ensure_signed_content_matches_contract!(validation_document)

    validation_result
  ensure
    validation_blob&.purge
  end

  def ensure_signed_content_matches_contract!(validation_document)
    # TODO: This check is currently only performed for Podpisuj sessions, but it should be extended to all session types.
    AutogramEnvironment.autogram_service.ensure_documents_equal(old: contract.documents, new: validation_document) if podpisuj?
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
