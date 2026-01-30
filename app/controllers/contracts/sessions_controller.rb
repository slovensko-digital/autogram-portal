class Contracts::SessionsController < ApplicationController
  before_action :set_contract
  before_action :set_session, except: [ :create ]
  before_action :set_recipient, only: [ :create, :show ]
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

    render @session
  end

  def show
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
    return head :not_found unless @session.eidentita? || @session.autogram?

    if params[:file].present?
      @session.accept_signed_file(Base64.encode64(params[:file].tempfile.read))
      render json: { success: true }
    elsif params[:signed_document].present?
      @session.accept_signed_file(params[:signed_document])
      render json: { success: true }
    else
      render json: { error: "No file provided" }, status: :bad_request
    end
  rescue => e
    Rails.logger.error "Error uploading signed document: #{e.message}"
    @session.mark_failed!(e.message) if @session.respond_to?(:mark_failed!)
    render json: { error: e.message }, status: :internal_server_error
  end

  def get_webhook
    return head :not_found unless @session.avm?
    @session.process_webhook(request.raw_post)
    head :ok
  end

  def standard_webhook
    return head :not_found unless @session.avm?
    @session.process_webhook(request.raw_post)
    head :ok
  end

  private

  def set_contract
    @contract = Contract.find_by!(uuid: params[:contract_id])
  end

  def set_session
    @session = @contract.sessions.find(params[:id])
  end

  def set_recipient
    if params[:recipient]
      @recipient = @contract.recipients.find_by_uuid!(params[:recipient])
      raise ActiveRecord::RecordNotFound if @recipient.signed_contract?(@contract)
    end
  end

  def create_eidentita_session
    if @recipient
      session = @recipient.sessions.where(contract: @contract, type: "EidentitaSession").pending.first
      return session if session
    else
      return @contract.current_eidentita_session if @contract.has_active_eidentita_session?
    end

    result = AutogramEnvironment.eidentita_service.initiate_signing(@contract)
    raise result[:error] if result[:error]

    @contract.sessions.create!(
      type: "EidentitaSession",
      signing_started_at: result[:signing_started_at],
      user: current_user,
      recipient: @recipient
    )
  end

  def create_avm_session
    if @recipient
      session = @recipient.sessions.where(contract: @contract, type: "AvmSession").pending.first
      return session if session
    else
      return @contract.current_avm_session if @contract.has_active_avm_session?
    end

    result = AutogramEnvironment.avm_service.initiate_signing(@contract)

    avm_session = @contract.sessions.create!(
      type: "AvmSession",
      document_identifier: result[:document_identifier],
      encryption_key: result[:encryption_key],
      signing_started_at: result[:signing_started_at],
      user: current_user,
      recipient: @recipient
    )

    Avm::SigningPollJob.perform_later(avm_session)

    avm_session
  end

  def create_autogram_session
    if @recipient
      session = @recipient.sessions.where(contract: @contract, type: "AutogramSession").pending.first
      return session if session
    else
      return @contract.current_autogram_session if @contract.has_active_autogram_session?
    end

    @contract.sessions.create!(
      type: "AutogramSession",
      signing_started_at: Time.current,
      user: current_user,
      recipient: @recipient
    )
  end
end
