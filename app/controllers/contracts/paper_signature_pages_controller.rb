module Contracts
  # Pages of a recipient's paper signature: photos or a PDF scan added to the draft, their order and
  # their content for the thumbnails. Pages are private, so they are served only here, to the recipient
  # of the signing link, and only while their paper signature is open.
  class PaperSignaturePagesController < ApplicationController
    include PaperSignerResolution

    before_action :set_page, only: [ :show, :update, :destroy ]

    def create
      PaperSignature.open_for!(@signer_contract).add_pages!(params[:files])

      redirect_to paper_signature_page_path, status: :see_other
    rescue PaperSignature::InvalidUpload => e
      redirect_to paper_signature_page_path, alert: e.message, status: :see_other
    end

    def show
      send_data @page.file.download, type: @page.file.content_type, disposition: "inline", filename: @page.file.filename.to_s
    rescue ActiveStorage::FileNotFoundError
      head :not_found
    end

    # Moves the page to params[:position] (1 is the first page).
    def update
      @paper_signature.move_page!(@page, params[:position].to_i)

      redirect_to paper_signature_page_path, status: :see_other
    end

    def destroy
      @paper_signature.remove_page!(@page)

      redirect_to paper_signature_page_path, status: :see_other
    end

    private

    def set_page
      @paper_signature = @signer_contract.paper_signatures.open.first
      raise ActiveRecord::RecordNotFound unless @paper_signature

      @page = @paper_signature.pages.find(params[:id])
    end
  end
end
