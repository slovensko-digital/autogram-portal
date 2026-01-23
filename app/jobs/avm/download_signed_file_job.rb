module Avm
  class DownloadSignedFileJob < ApplicationJob
    def perform(avm_session, avm_service: AutogramEnvironment.avm_service)
      return unless avm_session.pending?

      signed_document = avm_service.download_signed_document(
        avm_session.document_id,
        avm_session.encryption_key
      )

      avm_session.contract.accept_signed_file(signed_document)
      avm_session.mark_completed!
    rescue => e
      avm_session.mark_failed!("Stiahnutie podpísaného dokumentu zlyhalo: #{e.message}")
      avm_session.broadcast_signing_error("Stiahnutie podpísaného dokumentu zlyhalo: #{e.message}")
      throw e
    end
  end
end
