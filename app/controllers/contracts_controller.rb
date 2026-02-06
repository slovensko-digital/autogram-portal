class ContractsController < ApplicationController
  before_action :set_contract, except: [ :new, :index, :create ]
  before_action :verify_author, only: [ :show, :update, :destroy ]
  before_action :allow_iframe, only: [ :iframe ]

  def index
    @contracts = current_user.contracts.where(bundle: nil).includes(:user, :documents).order(created_at: :desc)
  end

  def new
    @contract = Contract.new
  end

  def create
    @contract = Contract.new(
      user: current_user,
      documents: [ Document.new(params.require(:document).permit(:blob)) ]
    )

    @contract.save!

    redirect_to @contract

  rescue ActiveRecord::RecordInvalid
    render :new, locals: { errors: @contract.errors }, status: :unprocessable_entity
  end

  def show
    @previous_page = request.referrer
  end

  def actions
    render partial: "actions", locals: { previous_page: params[:previous_page] }
  end

  def signature_extension
    render partial: "signature_extension"
  end

  def signature_parameters
    @next_step = params[:target_step]
    render partial: "signature_parameters"
  end

  def extend_signatures
    return head :unauthorized unless current_user
    return redirect_to @contract, alert: t("documents.alerts.all_signatures_have_timestamps") unless @contract.extendable_signatures?

    begin
      @contract.extend_signatures!
      redirect_to @contract, notice: t("documents.alerts.signature_extended_successfully")
    rescue => e
      redirect_to @contract, alert: t("documents.alerts.failed_to_extend_signatures", error: e.message)
    end
  end

  def sign
  end

  def signature_apps
    # Load recipient from URL parameter (magic link) OR derive from current user
    if params[:recipient_uuid]
      @recipient = @contract.recipients.find_by(uuid: params[:recipient_uuid])
    elsif current_user
      # Logged-in user: find their recipient by email match
      @recipient = @contract.recipients.find_by(email: current_user.email)
    end

    # Get eID card generation from params (if just redirected from onboarding), user, or session
    @eid_card_generation = params[:eid_card_generation]&.to_i || current_user&.eid_card_generation || session[:eid_card_generation]
  end

  def physical_signing
    # Load recipient from URL parameter (magic link) OR derive from current user
    if params[:recipient_uuid]
      @recipient = @contract.recipients.find_by(uuid: params[:recipient_uuid])
    elsif current_user
      # Logged-in user: find their recipient by email match
      @recipient = @contract.recipients.find_by(email: current_user.email)
    end

    # Redirect if recipient already signed
    if @recipient&.signed_contract?(@contract)
      redirect_path = if @contract.bundle
        sign_bundle_path(@contract.bundle, recipient: @recipient&.uuid)
      else
        sign_contract_path(@contract, recipient_uuid: @recipient&.uuid)
      end
      redirect_to redirect_path
    end
  end

  def create_physical_session
    recipient_uuid = params[:recipient_uuid]
    @recipient = @contract.recipients.find_by(uuid: recipient_uuid) if recipient_uuid

    submitted_date = params[:submitted_date]

    # Create physical session
    physical_session = PhysicalSession.create!(
      contract: @contract,
      user: current_user,
      recipient: @recipient,
      status: :pending
    )
    physical_session.submitted_date = submitted_date
    physical_session.save!

    redirect_to sign_contract_path(@contract), notice: 'Physical signing information submitted successfully.'
  rescue ActiveRecord::RecordInvalid => e
    redirect_to physical_signing_contract_path(@contract, recipient_uuid: recipient_uuid),
                alert: "Failed to submit: #{e.message}"
  end

  def signed_document
    redirect_to rails_blob_url(@contract.signed_document, disposition: "attachment"), allow_other_host: true
  end

  def validate
    @validation_result = @contract.validation_result
    if @validation_result.nil?
      respond_to do |format|
        format.html do
          render "validate_error", locals: { errors: [ "It is not possible to validate signatures for a contract with multiple documents." ] }
        end
        format.json do
          render json: { errors: [ "It is not possible to validate signatures for a contract with multiple documents." ] }, status: :unprocessable_entity
        end
      end
      return
    end

    begin
      respond_to do |format|
        format.html do
          render "validate"
        end
        format.json do
          signatures = @validation_result.signatures.flatten

          render json: {
            hasSignatures: @validation_result.has_signatures,
            signatures: signatures.map { |sig| format_signature_for_json(sig) },
            documentInfo: @validation_result.document_info,
            errors: @validation_result.errors
          }
        end
      end
    rescue => e
      respond_to do |format|
        format.html do
          render "validate_error", locals: { errors: [ e.message ] }
        end
        format.json do
          render json: { errors: [ e.message ] }, status: :unprocessable_entity
        end
      end
    end
  end

  def update
    if @contract.update(contract_params)
      @contract.save!
      if params[:next_step] == "request_signature"
        bundle = Bundle.create!(contracts: [ @contract ], author: current_user)
        redirect_to bundle
      elsif params[:next_step] == "sign"
        redirect_to sign_contract_path(@contract)
      else
        redirect_to @contract
      end
    else
      render :show, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid
    render :show, locals: { flash: @contract.errors }, status: :unprocessable_entity
  end

  def destroy
    return redirect_to @contract, alert: I18n.t("contracts.destroy.failure_bundle_attached") if @contract.bundle.present?

    if @contract.destroy
      if current_user
        redirect_to contracts_path, notice: I18n.t("contracts.destroy.success")
      else
        redirect_to root_path, notice: I18n.t("contracts.destroy.success")
      end
    else
      redirect_to @contract, alert: I18n.t("contracts.destroy.failure", error: e.message)
    end
  end

  def iframe
    no_header
    no_footer
    no_flash

    if params[:no_preview]
      render template: "contracts/iframe_no_preview"
    end
  end

  private

  def verify_author
    if @contract.user && @contract.user != current_user
      redirect_to root_path, alert: t("contracts.alerts.unauthorized_edit_attempt")
    end
  end

  def set_contract
    @contract = Contract.includes(:bundle).find_by!(uuid: params[:id])
  end

  def contract_params
    params.require(:contract).permit(
      :uuid,
      :allowed_method,
      documents_attributes: [ :id, :blob, :_destroy ],
      signature_parameters_attributes: [ :id, :format_container_combination, :add_content_timestamp ]
    )
  end

  def signed_document_param
    params.require(:signed_document)
  end

  def format_signature_for_json(signature)
    {
      signerName: signature[:signer_name],
      signingTime: signature[:signing_time]&.iso8601,
      signatureLevel: signature[:signature_level],
      validationResult: signature[:validation_result],
      valid: signature[:valid],
      certificateInfo: {
        subject: signature.dig(:certificate_info, :subject),
        issuer: signature.dig(:certificate_info, :issuer),
        qualification: signature.dig(:certificate_info, :qualification)
      },
      timestampInfo: signature[:timestamp_info] ? {
        count: signature.dig(:timestamp_info, :count),
        qualified: signature.dig(:timestamp_info, :qualified),
        timestamps: signature.dig(:timestamp_info, :timestamps)&.map do |ts|
          {
            type: ts[:type],
            time: ts[:time]&.iso8601,
            subject: ts[:subject],
            qualification: ts[:qualification]
          }
        end
      } : nil
    }
  end
end
