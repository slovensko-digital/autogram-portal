# == Schema Information
#
# Table name: avm_sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  encryption_key     :string
#  error_message      :text
#  signing_started_at :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  document_id        :string
#
class AvmSession < ApplicationRecord
  # TODO encrypt sensitive fields

  has_one :session, as: :sessionable, dependent: :destroy

  delegate :contract, :status, :status=, :pending?, :completed?, to: :session

  validates :document_id, :encryption_key, :signing_started_at, presence: true

  after_update_commit :broadcast_status_change

  def avm_url
    base_url = ENV.fetch("AVM_URL", "https://autogram.slovensko.digital").chomp("/")
    "#{base_url}/api/v1/qr-code?guid=#{document_id}&key=#{encryption_key}"
  end

  def expired?
    return false unless signing_started_at
    Time.current > signing_started_at + 10.minutes # 10 minute timeout
  end

  def mark_completed!
    session.update!(status: :completed)
    update!(completed_at: Time.current)
  end

  def mark_failed!(message=nil)
    session.update!(status: :failed)
    update!(error_message: message || "Signing failed", completed_at: Time.current)
  end

  def mark_expired!
    session.update!(status: :expired)
    update!(completed_at: Time.current)
  end

  def process_webhook(_)
    Avm::DownloadSignedFileJob.perform_later(self)
  end

  def broadcast_status_change
    return unless session.saved_change_to_status?

    case status
    when "completed"
      # Signing success is now handled by Contract.accept_signed_file
      # which is called before this status change occurs
    when "failed"
      broadcast_signing_error("Signing failed")
    when "expired"
      broadcast_signing_error("Signing expired")
    end
  end

  def broadcast_signing_error(error_message)
    Turbo::StreamsChannel.broadcast_replace_to(
      self,
      target: "signature_actions_#{contract.uuid}",
      partial: "contracts/sessions/error",
      locals: {
        contract: contract,
        error: error_message
      }
    )
  end
end
