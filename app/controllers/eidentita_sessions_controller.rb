class EidentitaSessionsController < ApplicationController
  before_action :set_contract, :set_eidentita_session
  skip_before_action :verify_authenticity_token, only: [ :upload ]

  def json
    eidentita_service = EidentitaService.new
    json_payload = eidentita_service.build_json_payload(@contract, @eidentita_session)

    render json: json_payload
  end

  def document
    document = @contract.documents_to_sign.first
    unless document&.blob&.attached?
      render plain: "Document not found", status: :not_found
      return
    end

    send_data document.content,
              filename: document.filename,
              type: document.content_type,
              disposition: "attachment"
  end

  def upload
    if params[:file].present?
      @contract.accept_signed_file(Base64.encode64(params[:file].tempfile.read))
      render json: { success: true }
    else
      render json: { error: "No file provided" }, status: :bad_request
    end
  rescue => e
    Rails.logger.error "Error uploading signed document: #{e.message}"
    @eidentita_session&.mark_failed!(e.message)
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def set_contract
    @contract = Contract.find_by!(uuid: params[:contract_id])
  end

  def set_eidentita_session
    @eidentita_session = @contract.eidentita_sessions.find(params[:id])
  end
end
