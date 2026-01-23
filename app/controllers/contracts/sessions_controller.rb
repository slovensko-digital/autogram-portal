class Contracts::SessionsController < ApplicationController
  before_action :set_contract
  before_action :set_session, except: [ :create ]
  skip_before_action :verify_authenticity_token, only: [ :upload, :get_webhook, :standard_webhook ]

  def create
    session_type = params[:type] || params[:application]

    @session = case session_type
    when "eidentita"
      create_eidentita_session
    when "avm"
      create_avm_session
    when "autogram"
      create_autogram_session
    else
      return render plain: "Invalid session type", status: :bad_request
    end

    redirect_to contract_session_path(@contract, @session)
  end

  def show
    case @session.sessionable_type
    when "EidentitaSession"
      show_eidentita
    when "AvmSession"
      show_avm
    when "AutogramSession"
      show_autogram
    end
  end

  def destroy
    @session.destroy
    head :ok
  end

  def parameters
    return render formats: [ :json ], partial: "eidentita" if @session.eidentita?
    return render formats: [ :json ], partial: "autogram" if @session.autogram?

    head :not_found
  end

  def download
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
    if @session.eidentita? || @session.autogram?
      handle_upload
    else
      head :not_found
    end
  end

  def get_webhook
    return head :not_found unless @session.avm?
    @session.sessionable.process_webhook(request.raw_post)
    head :ok
  end

  def standard_webhook
    return head :not_found unless @session.avm?
    @session.sessionable.process_webhook(request.raw_post)
    head :ok
  end

  private

  def set_contract
    @contract = Contract.find_by!(uuid: params[:contract_id])
  end

  def set_session
    @session = @contract.sessions.find(params[:id])
  end

  def create_eidentita_session
    return @contract.current_eidentita_session.session if @contract.has_active_eidentita_session?

    result = AutogramEnvironment.eidentita_service.initiate_signing(@contract)
    raise result[:error] if result[:error]

    eidentita_session = EidentitaSession.create!(signing_started_at: result[:signing_started_at])

    @contract.sessions.create!(sessionable: eidentita_session)
  end

  def create_avm_session
    return @contract.current_avm_session.session if @contract.has_active_avm_session?

    result = AutogramEnvironment.avm_service.initiate_signing(@contract)

    avm_session = AvmSession.create!(
      document_id: result[:document_id],
      encryption_key: result[:encryption_key],
      signing_started_at: result[:signing_started_at]
    )

    session = @contract.sessions.create!(sessionable: avm_session)

    Avm::SigningPollJob.perform_later(avm_session)

    session
  end

  def create_autogram_session
    @contract.sessions.create!(sessionable: AutogramSession.create!(signing_started_at: Time.current))
  end

  def show_eidentita
    render turbo_stream: turbo_stream.replace(
      "signature_actions_#{@contract.uuid}",
      partial: "eidentita",
      locals: {
        contract: @contract,
        session: @session.sessionable,
        cancel_url: determine_cancel_url
      }
    )
  end

  def show_avm
    render turbo_stream: turbo_stream.replace(
      "signature_actions_#{@contract.uuid}",
      partial: "avm",
      locals: {
        contract: @contract,
        session: @session.sessionable,
        cancel_url: determine_cancel_url
      }
    )
  end

  def show_autogram
    render turbo_stream: turbo_stream.replace(
      "signature_actions_#{@contract.uuid}",
      partial: "autogram",
      locals: {
        contract: @contract,
        session: @session,
        cancel_url: determine_cancel_url
      }
    )
  end

  def handle_upload
    if params[:file].present?
      @contract.accept_signed_file(Base64.encode64(params[:file].tempfile.read))
      render json: { success: true }
    elsif params[:signed_document].present?
      @contract.accept_signed_file(params[:signed_document])
      render json: { success: true }
    else
      render json: { error: "No file provided" }, status: :bad_request
    end
  rescue => e
    Rails.logger.error "Error uploading signed document: #{e.message}"
    @session.sessionable.mark_failed!(e.message) if @session.sessionable.respond_to?(:mark_failed!)
    render json: { error: e.message }, status: :internal_server_error
  end

  def determine_cancel_url
    signature_actions_contract_path(@contract)
  end
end
