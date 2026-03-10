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
    # TODO: Check if signed_file is a signed version of the original documents
    # AutogramEnvironment.autogram_service.validate_signed_file(signed_file, documents.map(&:blob))

    # TODO: Validate the signatures in the signed file
    # AutogramEnvironment.autogram_service.validate_signatures(signed_file, signature_parameters)

    # TODO: version signed document attachment to avoid overwriting in concurrent scenarios

    ActiveRecord::Base.transaction do
      new_filename = generate_signed_filename
      new_content_type = new_filename.ends_with?(".asice") ? "application/vnd.etsi.asic-e+zip" : "application/pdf"
      contract.signed_document.purge if contract.signed_document.attached?
      contract.signed_document.attach(
        io: StringIO.new(Base64.decode64(signed_file)),
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


  private

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
