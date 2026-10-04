class Contracts::SessionsController < ApplicationController
  class SessionCreationError < StandardError; end

  before_action :set_contract
  before_action :set_session, except: [ :create ]
  before_action :set_signer_contract, only: [ :create, :show, :request_verification, :verify_verification, :complete_signing ]
  before_action :ensure_prepared_signature_field_appearance_completed, only: [ :create, :show, :request_verification, :verify_verification, :complete_signing ]
  before_action :authorize_session_operation!
  before_action :redirect_if_completed, only: [ :show ]
  skip_before_action :verify_authenticity_token, only: [ :upload, :get_webhook, :standard_webhook ]
  # Cross-site iframes do not get the session cookie the token is checked against.
  skip_before_action :verify_authenticity_token, only: [ :request_verification, :verify_verification, :complete_signing ], if: -> { params[:iframe].present? }
  skip_before_action :ensure_tenant_selected, if: -> { params[:iframe].present? }
  before_action :allow_iframe

  rescue_from Pundit::NotAuthorizedError, with: -> { head :forbidden }

  def create
    session_type = params[:type] || params[:application]
    ensure_signature_request_limit!

    @session = case session_type
    when "ades"
      create_ades_session
    when "eidentita"
      create_eidentita_session
    when "avm"
      create_avm_session
    when "autogram"
      create_autogram_session
    when "podpisuj"
      create_podpisuj_session
    else
      return render plain: "Invalid session type", status: :bad_request
    end

    return if performed?

    render :show
  rescue SessionCreationError, ActiveRecord::RecordInvalid => e
    Rails.logger.warn("Failed to create signing session for contract #{@contract.uuid}: #{e.message}")
    @session_error_message = e.message
    render partial: "contracts/sessions/creation_error", status: :unprocessable_entity
  end

  def show
  end

  def request_verification
    return head :not_found unless @session.ades_evidence?

    SignatureVerificationService.new.request_code!(
      session: @session,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    render :show
  rescue SignatureVerificationService::Error => e
    @session.update!(error_message: e.message)
    render :show, status: :unprocessable_entity
  end

  def verify_verification
    return head :not_found unless @session.ades_evidence?

    SignatureVerificationService.new.verify_code!(
      session: @session,
      code: params[:verification_code],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    render :show
  rescue SignatureVerificationService::Error => e
    @session.update!(error_message: e.message)
    render :show, status: :unprocessable_entity
  end

  def complete_signing
    return head :not_found unless @session.ades_evidence?

    AutogramEnvironment.ades_signing_service.sign!(
      session: @session,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      app_host: request.host
    )

    render :show
  rescue AdesServerSigningService::Error => e
    @session.update!(error_message: e.message)
    render :show, status: :unprocessable_entity
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
    document = @contract.documents_to_sign_for(signer_contract: @session.signer_contract).first
    unless document&.blob&.attached?
      render plain: "Document not found", status: :not_found
      return
    end

    content = document.content
    if content.nil?
      render plain: "Document not found", status: :not_found
      return
    end

    send_data content,
              filename: document.filename,
              type: document.content_type,
              disposition: "attachment"
  rescue ActiveStorage::FileNotFoundError
    render plain: "Document not found", status: :not_found
  end

  def upload
    return head :not_found unless @session.eidentita? || @session.autogram? || @session.podpisuj?

    if params[:file].present?
      @session.accept_signed_file(Base64.strict_encode64(params[:file].tempfile.read))
      render json: { success: true }
    elsif params[:signed_document].present?
      @session.accept_signed_file(params[:signed_document])
      render json: { success: true }
    else
      render json: { error: t("session.errors.no_file") }, status: :bad_request
    end
  rescue => e
    if @session.podpisuj? && retryable_upload_error?(e)
      # The signer uploads the file by hand, so keep the session open and let them pick another file.
      Rails.logger.info "Rejected uploaded signed document: #{e.message}"
      return render json: { error: e.message }, status: :unprocessable_entity
    end

    Rails.logger.error "Error uploading signed document: #{e.message}"
    @session.update(error_message: e.message) if @session.respond_to?(:update)
    @session.mark_failed!(e.message) if @session.respond_to?(:mark_failed!)
    render json: { error: e.message }, status: :bad_request
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

  def retryable_upload_error?(error)
    error.is_a?(Session::InvalidSignedFileError) || error.is_a?(AutogramService::AutogramServiceError)
  end

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

      if @recipient.nil? && @contract.bundle.present? && policy(@contract.bundle).manage?
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

    if @signer_contract&.superseded? && @contract.bundle.present?
      redirect_to sign_bundle_path(@contract.bundle, recipient: @recipient&.uuid, iframe: params[:iframe]),
                  notice: t("bundles.sign.signature_no_longer_required")
      return
    end

    @signer_contract = AnonymousSigner.create!.signer_contracts.create!(contract: @contract) unless @signer_contract
  end

  def redirect_if_completed
    return if params[:show_completed].present?
    return unless @session.not_pending?

    redirect_path = if @contract.bundle
      sign_bundle_path(@contract.bundle, recipient: @recipient&.uuid, iframe: @session.iframe_param)
    else
      sign_contract_path(@contract, recipient: @recipient&.uuid, iframe: @session.iframe_param)
    end

    redirect_to redirect_path
  end

  def ensure_prepared_signature_field_appearance_completed
    return unless ades_evidence_flow_request?
    return unless @contract.prepared_signature_field_appearance_required_for?(recipient: @recipient, signer_contract: @signer_contract)

    if request.headers["Turbo-Frame"].present?
      render partial: "contracts/signature_field_appearance_required",
             locals: {
               frame_id: request.headers["Turbo-Frame"],
               contract: @contract,
               recipient: @recipient,
               resume_signing_method: "ades"
             }
      return
    end

    redirect_to visual_signing_contract_path(
      @contract,
      recipient: @recipient&.uuid,
      iframe: params[:iframe],
      purpose: "signature_field_appearance",
      resume_signing_method: "ades"
    )
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

  def create_ades_session
    existing = @signer_contract&.sessions&.pending&.where(type: "AdesEvidenceSession")&.first
    return persist_session_view_options(existing) if existing

    verification_channel = AdesEvidenceSession.verification_channel_for(@contract, recipient: @recipient)
    raise SessionCreationError, t("contracts.sessions.ades_evidence.missing_contact") if verification_channel.blank?

    persist_session_view_options(@signer_contract.sessions.create!(
      type: "AdesEvidenceSession",
      signing_started_at: Time.current,
      options: session_view_options.merge(
        "verification_channel" => verification_channel
      )
    ))
  end

  def ades_evidence_flow_request?
    if action_name == "create"
      (params[:type] || params[:application]) == "ades"
    else
      @session&.ades_evidence?
    end
  end

  def ensure_signature_request_limit!
    bundle = @contract.bundle
    return unless bundle&.signature_request_limit_reached_for?(@signer_contract&.recipient)

    raise SessionCreationError, t("plan_limits.signing_blocked", sender: bundle.sender_display_name)
  end

  def create_avm_session
    existing = @signer_contract&.sessions&.pending&.where(type: "AvmSession")&.first
    return persist_session_view_options(existing) if existing

    if AvmSession.unavailability_reasons(nil, @contract).include?(:timestamp_limit_reached)
      raise SessionCreationError, t("contracts.signature_apps.unavailable_reasons.timestamp_limit_reached")
    end

    result = AutogramEnvironment.avm_service.initiate_signing(@contract, signer_contract: @signer_contract)
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

  def create_podpisuj_session
    raise SessionCreationError, t("contracts.signature_apps.unavailable_reasons.method_not_allowed") unless @contract.standalone_qes_allowed?

    existing = @signer_contract&.sessions&.pending&.where(type: "PodpisujSession")&.first
    return persist_session_view_options(existing) if existing

    persist_session_view_options(@signer_contract.sessions.create!(
      type: "PodpisujSession",
      signing_started_at: Time.current,
      options: session_view_options
    ))
  end

  def authorize_session_operation!
    access = SigningSessionAccess.new(
      contract: @contract,
      session: @session,
      signer_contract: @signer_contract,
      token_authorized: session_token_authorized?
    )
    authorize [ :signing, access ]
  end

  def session_token_authorized?
    token = params[:session_token].presence
    return false unless token && @session

    SessionAccessToken.valid?(token: token, contract: @contract, session: @session)
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
