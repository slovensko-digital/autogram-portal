# == Schema Information
#
# Table name: eidentita_sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  error_message      :text
#  signing_started_at :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class EidentitaSession < ApplicationRecord
  has_one :session, as: :sessionable, dependent: :destroy

  delegate :contract, :status, :status=, to: :session

  validates :signing_started_at, presence: true

  after_update_commit :broadcast_status_change

  def eidentita_url
    url_options = Rails.application.config.action_controller.default_url_options || {}
    link_url = Rails.application.routes.url_helpers.parameters_contract_session_url(contract, session, **url_options)
    "sk.minv.sca://sign?qr=true&linkUrl=#{CGI.escape(link_url)}.json"
  end

  def eidentita_url_mobile
    url_options = Rails.application.config.action_controller.default_url_options || {}
    link_url = Rails.application.routes.url_helpers.parameters_contract_session_url(contract, session, **url_options)
    "sk.minv.sca://sign?qr=false&linkUrl=#{CGI.escape(link_url)}.json"
  end

  def mark_completed!
    session.update!(status: :completed)
    update!(completed_at: Time.current)
  end

  def mark_failed!(error = nil)
    session.update!(status: :failed)
    update!(error_message: error || "Signing failed", completed_at: Time.current)
  end

  def mark_expired!
    session.update!(status: :expired)
    update!(completed_at: Time.current)
  end

  def broadcast_status_change
    return unless session.saved_change_to_status?

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
      partial: "contracts/sessions/error",
      locals: {
        contract: contract,
        error: error_message
      }
    )
  end
end
