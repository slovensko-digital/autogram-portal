# == Schema Information
#
# Table name: avm_sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  encryption_key     :string
#  error_message      :text
#  signing_started_at :datetime
#  status             :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  contract_id        :bigint           not null
#  document_id        :string
#
# Indexes
#
#  index_avm_sessions_on_contract_id  (contract_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#
class AvmSession < ApplicationRecord
  # TODO encrypt sensitive fields

  belongs_to :contract

  enum :status, {
    pending: "pending",
    completed: "completed",
    failed: "failed",
    expired: "expired"
  }

  validates :document_id, :encryption_key, :signing_started_at, presence: true

  scope :active, -> { where(status: :pending) }
  scope :recent, -> { order(created_at: :desc) }

  after_update_commit :broadcast_status_change

  def avm_url
    # TODO: do not hardcode the base URL
    "https://autogram.slovensko.digital/api/v1/qr-code?guid=#{document_id}&key=#{encryption_key}"
  end

  def expired?
    return false unless signing_started_at
    Time.current > signing_started_at + 15.minutes # 15 minute timeout
  end

  def mark_completed!
    update!(status: :completed, completed_at: Time.current)
  end

  def mark_failed!
    update!(status: :failed, error_message: "Signing failed", completed_at: Time.current)
  end

  def mark_expired!
    update!(status: :expired, completed_at: Time.current)
  end

  def broadcast_status_change
    return unless saved_change_to_status?

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
      "contract_#{contract.id}",
      target: "signature_actions_#{contract.id}",
      partial: "contracts/signature_error",
      locals: {
        contract: contract,
        error: error_message
      }
    )
  end


end
