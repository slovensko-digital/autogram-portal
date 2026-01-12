# == Schema Information
#
# Table name: eidentita_sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  error_message      :text
#  signing_started_at :datetime
#  status             :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  contract_id        :bigint           not null
#
# Indexes
#
#  index_eidentita_sessions_on_contract_id  (contract_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#
class EidentitaSession < ApplicationRecord
  belongs_to :contract

  enum :status, {
    pending: "pending",
    completed: "completed",
    failed: "failed",
    expired: "expired"
  }

  validates :signing_started_at, presence: true

  scope :active, -> { where(status: :pending) }
  scope :recent, -> { order(created_at: :desc) }

  after_update_commit :broadcast_status_change

  def eidentita_url
    link_url = Rails.application.routes.url_helpers.json_contract_eidentita_session_url(contract, self)
    "sk.minv.sca://sign?qr=true&linkUrl=#{CGI.escape(link_url)}"
  end

  def eidentita_url_mobile
    link_url = Rails.application.routes.url_helpers.json_contract_eidentita_session_url(contract, self)
    "sk.minv.sca://sign?qr=false&linkUrl=#{CGI.escape(link_url)}"
  end

  def mark_completed!
    update!(status: :completed, completed_at: Time.current)
  end

  def mark_failed!(error = nil)
    update!(status: :failed, error_message: error || "Signing failed", completed_at: Time.current)
  end

  def mark_expired!
    update!(status: :expired, completed_at: Time.current)
  end

  def broadcast_status_change
    return unless saved_change_to_status?

    case status
    when "completed"
      # Signing success is handled by Contract.accept_signed_file
    when "failed"
      broadcast_signing_error("Signing failed")
    when "expired"
      broadcast_signing_error("Signing expired")
    end
  end

  def broadcast_signing_error(error_message)
    Turbo::StreamsChannel.broadcast_replace_to(
      "contract_#{contract.uuid}",
      target: "signature_actions_#{contract.uuid}",
      partial: "contracts/signature_error",
      locals: {
        contract: contract,
        error: error_message
      }
    )
  end
end
