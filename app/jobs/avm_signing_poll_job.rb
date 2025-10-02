class AvmSigningPollJob < ApplicationJob
  retry_on StandardError, wait: :exponentially_longer, attempts: 10

  def perform(avm_session)
    return avm_session.mark_expired! if avm_session.expired?
    return unless avm_session.pending?

    begin
      result = AutogramEnvironment.autogram_service.check_avm_signing_status(
        avm_session.document_id,
        avm_session.signing_started_at,
        avm_session.encryption_key
      )

      case result[:status]
      when "completed"
        signed_document = AutogramEnvironment.autogram_service.download_avm_signed_document(
          avm_session.document_id,
          avm_session.encryption_key
        )

        avm_session.contract.accept_signed_file(signed_document)
        avm_session.mark_completed!

      when "failed"
        avm_session.mark_failed!

      when "pending"
        AvmSigningPollJob.set(wait: 2.seconds).perform_later(avm_session)

      else
        avm_session.mark_failed!("Neznámy status: #{result[:status]}")
        avm_session.broadcast_signing_error("Neznámy status: #{result[:status]}")
      end

    rescue => e
      if Time.current < avm_session.signing_started_at + 14.minutes
        AvmSigningPollJob.set(wait: 5.seconds).perform_later(avm_session)
      else
        avm_session.mark_failed!("Polling failed: #{e.message}")
        avm_session.broadcast_signing_error("Polling failed: #{e.message}")
      end
    end
  end
end
