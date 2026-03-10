class Contracts::SessionsController < ApplicationController
  before_action :set_contract
  before_action :set_session, except: [ :create ]
  before_action :set_signer_contract, only: [ :create, :show ]
  before_action :redirect_if_completed, only: [ :show ]
  skip_before_action :verify_authenticity_token, only: [ :upload, :get_webhook, :standard_webhook ]
  before_action :allow_iframe

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

  def set_signer_contract
    if params[:recipient]
      @recipient = @contract.recipients.find_by_uuid!(params[:recipient])
    elsif current_user
      @recipient = @contract.recipients.find_by(user: current_user) ||
                   @contract.recipients.find_by(email: current_user.email)

      if @recipient.nil? && @contract.bundle.present? && current_user == @contract.bundle.author
        @recipient = @contract.bundle.recipients.find_or_create_by!(email: current_user.email) do |r|
          r.user = current_user
          r.name = current_user.display_name
        end
      end
    end

    if @recipient
      recipient_signer = @recipient.recipient_signer || @recipient.create_recipient_signer!
      @signer_contract = recipient_signer.signer_contracts.find_or_create_by!(contract: @contract)
    elsif current_user
      user_signer = UserSigner.find_or_create_by!(user: current_user)
      @signer_contract = user_signer.signer_contracts.find_or_create_by!(contract: @contract)
    elsif @contract.user.nil?
      @signer_contract = @contract.signer_contracts
                                  .joins(:signer)
                                  .find_by(signers: { type: "AnonymousSigner" })
      unless @signer_contract
        @signer_contract = AnonymousSigner.create!.signer_contracts.create!(contract: @contract)
      end
    end

    raise ActiveRecord::RecordNotFound if @signer_contract&.signed? && @contract.bundle.present?
  end

  def redirect_if_completed
    return unless @session.not_pending?

    redirect_path = if @contract.bundle
      sign_bundle_path(@contract.bundle, recipient: @recipient&.uuid)
    else
      sign_contract_path(@contract, recipient: @recipient&.uuid)
    end

    redirect_to redirect_path
  end

  def create_eidentita_session
    existing = @signer_contract.sessions.pending.where(type: "EidentitaSession").first
    return existing if existing

    result = AutogramEnvironment.eidentita_service.initiate_signing(@contract)
    raise result[:error] if result[:error]

    @signer_contract.sessions.create!(
      type: "EidentitaSession",
      signing_started_at: result[:signing_started_at]
    )
  end

  def create_avm_session
    existing = @signer_contract.sessions.pending.where(type: "AvmSession").first
    return existing if existing

    result = AutogramEnvironment.avm_service.initiate_signing(@contract)

    avm_session = @signer_contract.sessions.create!(
      type: "AvmSession",
      document_identifier: result[:document_identifier],
      encryption_key: result[:encryption_key],
      signing_started_at: result[:signing_started_at]
    )

    Avm::SigningPollJob.perform_later(avm_session)

    avm_session
  end

  def create_autogram_session
    existing = @signer_contract.sessions.pending.where(type: "AutogramSession").first
    return existing if existing

    @signer_contract.sessions.create!(
      type: "AutogramSession",
      signing_started_at: Time.current
    )
  end
end
