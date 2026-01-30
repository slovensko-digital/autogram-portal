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
#  contract_id        :bigint           not null
#  recipient_id       :bigint
#  user_id            :bigint
#
# Indexes
#
#  index_sessions_on_contract_id   (contract_id)
#  index_sessions_on_recipient_id  (recipient_id)
#  index_sessions_on_type          (type)
#  index_sessions_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (recipient_id => recipients.id)
#  fk_rails_...  (user_id => users.id)
#
class Session < ApplicationRecord
  belongs_to :contract
  belongs_to :user, optional: true
  belongs_to :recipient, optional: true

  enum :status, {
    pending: 0,
    signed: 1,
    failed: 2,
    expired: 3,
    canceled: 4
  }

  validates :signing_started_at, presence: true

  scope :recent, -> { order(created_at: :desc) }

  after_update_commit :broadcast_status_change, if: :saved_change_to_status?
  after_update_commit -> { touch(:completed_at) }, if: -> { saved_change_to_status? && !pending? }

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

      if recipient.nil? && user.present? && contract.bundle.present?
        update!(recipient: contract.bundle.recipients.where(user: user).first)
      end

      signed!
    end

    contract.sessions.pending.each(&:canceled!)
    contract.notify_signed!(recipient: recipient, signer: user)
  end

  def generate_signed_filename
    if contract.documents.count == 1
      original_filename = contract.documents.first.blob.filename.base
      return "#{original_filename}-signed.#{contract.signature_parameters.container.present? ? 'asice' : 'pdf'}"
    end

    "contract-#{id}-signed.#{contract.signature_parameters.container.present? ? 'asice' : 'pdf'}"
  end


  protected

  def broadcast_status_change
    case status
    when "failed"
      broadcast_signing_error(error_message || "Signing failed")
    when "expired"
      broadcast_signing_error("Signing expired")
    end
  end

  def broadcast_signing_error(error_message)
    Turbo::StreamsChannel.broadcast_replace_to(
      "contract_#{contract.uuid}",
      target: "signature_actions_#{contract.uuid}",
      partial: "contracts/sessions/error",
      locals: {
        contract: contract,
        error: error_message
      }
    )
  end
end
