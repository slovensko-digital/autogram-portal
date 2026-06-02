class Contracts::SessionsController < ApplicationController
  class SessionCreationError < StandardError; end

  before_action :set_contract
  before_action :set_session, except: [ :create ]
  before_action :set_signer_contract, only: [ :create, :show ]
  before_action :authorize_session_access!, only: [ :parameters, :download, :upload ]
  before_action :authorize_session_destroy!, only: [ :destroy ]
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
  rescue SessionCreationError, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("Failed to create signing session for contract #{@contract.uuid}: #{e.message}")
    @session_error_message = e.message
    render partial: "contracts/sessions/creation_error", status: :unprocessable_entity
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
      @session.accept_signed_file(Base64.strict_encode64(params[:file].tempfile.read))
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
      @recipient = @contract.recipients.active.find_by_uuid(params[:recipient])

      unless @recipient
        withdrawn_recipient = @contract.recipients.withdrawn.find_by_uuid(params[:recipient])
        if withdrawn_recipient&.bundle
          redirect_to sign_bundle_path(withdrawn_recipient.bundle, recipient: withdrawn_recipient.uuid)
          return
        end

        raise ActiveRecord::RecordNotFound
      end
    elsif current_user
      @recipient = @contract.recipients.active.find_by(user: current_user) ||
                   @contract.recipients.active.find_by(email: current_user.email)

      if @recipient.nil? && @contract.bundle.present? && current_user == @contract.bundle.author
        @recipient = Recipient.find_or_create_author_proxy_for!(bundle: @contract.bundle, user: current_user)
      end
    end

    if @recipient
      recipient_signer = @recipient.recipient_signer || @recipient.create_recipient_signer!
      @signer_contract = recipient_signer.signer_contracts.find_or_create_by!(contract: @contract)
    elsif current_user
      user_signer = UserSigner.find_or_create_by!(user: current_user)
      @signer_contract = user_signer.signer_contracts.find_or_create_by!(contract: @contract)
    elsif @contract.bundle.present?
      @signer_contract = @contract.signer_contracts
                                  .joins(:signer)
                                  .find_by(signers: { type: "AnonymousSigner" })
      unless @signer_contract
        @signer_contract = AnonymousSigner.create!.signer_contracts.create!(contract: @contract)
      end
    end

    raise ActiveRecord::RecordNotFound if @signer_contract&.signed? && @contract.bundle.present?

    @signer_contract = AnonymousSigner.create!.signer_contracts.create!(contract: @contract) unless @signer_contract
  end

  def redirect_if_completed
    return unless @session.not_pending?

    redirect_path = if @contract.bundle
      sign_bundle_path(@contract.bundle, recipient: @recipient&.uuid, iframe: @session.iframe_param)
    else
      sign_contract_path(@contract, recipient: @recipient&.uuid, iframe: @session.iframe_param)
    end

    redirect_to redirect_path
  end

  def create_eidentita_session
    existing = @signer_contract&.sessions&.pending&.where(type: "EidentitaSession")&.first
    return persist_session_view_options(existing) if existing

    result = AutogramEnvironment.eidentita_service.initiate_signing(@contract)
    raise SessionCreationError, result[:error] if result[:error]

    persist_session_view_options(@signer_contract.sessions.create!(
      type: "EidentitaSession",
      signing_started_at: result[:signing_started_at],
      options: session_view_options
    ))
  end

  def create_avm_session
    existing = @signer_contract&.sessions&.pending&.where(type: "AvmSession")&.first
    return persist_session_view_options(existing) if existing

    result = AutogramEnvironment.avm_service.initiate_signing(@contract)
    raise SessionCreationError, result[:error] if result[:error]

    unless result[:document_identifier].present? && result[:encryption_key].present? && result[:signing_started_at].present?
      raise SessionCreationError, t("errors.signing_failed")
    end

    avm_session = @signer_contract.sessions.create!(
      type: "AvmSession",
      signing_started_at: result[:signing_started_at],
      options: session_view_options.merge(
        "document_identifier" => result[:document_identifier],
        "encryption_key" => result[:encryption_key]
      )
    )

    Avm::SigningPollJob.perform_later(avm_session)

    persist_session_view_options(avm_session)
  end

  def create_autogram_session
    existing = @signer_contract&.sessions&.pending&.where(type: "AutogramSession")&.first
    return persist_session_view_options(existing) if existing

    persist_session_view_options(@signer_contract.sessions.create!(
      type: "AutogramSession",
      signing_started_at: Time.current,
      options: session_view_options
    ))
  end

  def authorize_session_access!
    return if session_token_authorized? || allowed_user_for_session?

    head :forbidden
  end

  def authorize_session_destroy!
    return if allowed_user_for_session?

    head :forbidden
  end

  def session_token_authorized?
    token = params[:session_token].presence
    return false unless token

    SessionAccessToken.valid?(token: token, contract: @contract, session: @session)
  end

  def allowed_user_for_session?
    return false unless current_user
    return true if @contract.user == current_user
    return true if @contract.bundle&.author == current_user

    signer = @session.signer

    case signer
    when UserSigner
      signer.user == current_user
    when RecipientSigner
      recipient = signer.recipient
      return false if recipient&.withdrawn?

      recipient&.user == current_user || recipient&.email == current_user.email
    else
      false
    end
  end

  def session_view_options
    {}.tap do |options|
      options["iframe"] = params[:iframe] if params[:iframe].present?
    end
  end

  def persist_session_view_options(session)
    return session if session_view_options.empty?

    merged_options = (session.options || {}).merge(session_view_options)
    session.update!(options: merged_options) if session.options != merged_options
    session
  end
end
