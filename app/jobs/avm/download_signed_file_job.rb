module Avm
  class DownloadSignedFileJob < ApplicationJob
    def perform(avm_session, avm_service: AutogramEnvironment.avm_service)
      return unless avm_session.pending?

      signed_document = avm_service.download_signed_document(
        avm_session.document_identifier,
        avm_session.encryption_key
      )

      avm_session.accept_signed_file(signed_document)
    rescue => e
      message = signed_file_error?(e) ? e.message : "Stiahnutie podpísaného dokumentu zlyhalo: #{e.message}"
      avm_session.mark_failed!(message)
      avm_session.broadcast_signing_error(message)
      throw e
    end

    private

    # The downloaded file was rejected, with a message already written for the signer.
    def signed_file_error?(error)
      error.is_a?(Session::InvalidSignedFileError) ||
        error.is_a?(Session::SignatureNoLongerRequiredError) ||
        error.is_a?(AutogramService::AutogramServiceError)
    end
  end
end
