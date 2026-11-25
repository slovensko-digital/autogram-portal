module Contracts
  # The page where a recipient signs on paper (screens 2–4 and 6): they download the document to print
  # it, upload photos or a scan of the signed pages into a draft and submit it for the sender's review.
  class PaperSignaturesController < ApplicationController
    include PaperSignerResolution

    # Opens a draft right away, so pages can come from a phone before anything is uploaded here.
    def show
      @paper_signature = PaperSignature.open_for!(@signer_contract)
    end

    def submit
      paper_signature = @signer_contract.paper_signatures.open.first
      submitted = paper_signature&.submit!

      redirect_to paper_signature_page_path, alert: (not_submitted_alert(paper_signature) unless submitted), status: :see_other
    rescue PaperSignature::InvalidUpload => e
      redirect_to paper_signature_page_path, alert: e.message, status: :see_other
    end

    # Discards the draft or the scan awaiting review; with params[:restart] the recipient uploads
    # another scan, otherwise they return to sign another way.
    def destroy
      @signer_contract.paper_signatures.open.find_each(&:cancel!)

      if params[:restart].present?
        redirect_to paper_signature_page_path, status: :see_other
      else
        redirect_to helpers.signing_page_path(@contract, recipient: @recipient), notice: t("paper_signatures.notices.discarded"), status: :see_other
      end
    end

    private

    # Nothing when the scan was submitted meanwhile (e.g. from a phone).
    def not_submitted_alert(paper_signature)
      return t("paper_signatures.alerts.no_pages") unless paper_signature
      return if paper_signature.reload.submitted?

      paper_signature.pages.exists? ? t("paper_signatures.alerts.pages_changed") : t("paper_signatures.alerts.no_pages")
    end
  end
end
