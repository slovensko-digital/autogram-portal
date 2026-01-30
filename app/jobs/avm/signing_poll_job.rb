module Avm
  class SigningPollJob < ApplicationJob
    def perform(avm_session, avm_service: AutogramEnvironment.avm_service)
      return avm_session.mark_expired! if avm_session.expired?
      return unless avm_session.pending?

      begin
        result = avm_service.check_signing_status(
          avm_session.document_identifier,
          avm_session.signing_started_at,
          avm_session.encryption_key
        )

        case result[:status]
        when "completed"
          Avm::DownloadSignedFileJob.perform_later(avm_session)

        when "failed"
          avm_session.mark_failed!

        when "pending"
          Avm::SigningPollJob.set(wait: 2.seconds).perform_later(avm_session)

        else
          avm_session.mark_failed!("Neznámy status: #{result[:status]}")
          avm_session.broadcast_signing_error("Neznámy status: #{result[:status]}")
        end

      rescue => e
        if Time.current < avm_session.signing_started_at + 14.minutes
          raise e # let the job retry
        else
          avm_session.mark_failed!("Polling failed: #{e.message}")
          avm_session.broadcast_signing_error("Polling failed: #{e.message}")
        end
      end
    end
  end
end
