class ContractsController < ApplicationController
  before_action :set_contract, only: [ :show, :sign, :sign_avm, :destroy, :signed_document, :validate, :edit, :iframe ]
  skip_before_action :verify_authenticity_token, only: [ :iframe, :sign_avm, :sign ]

  before_action :allow_iframe, only: [ :iframe ]

  def index
    @contracts = current_user.contracts.includes(:user, :documents).order(created_at: :desc)
  end

  def new
    @contract = Contract.new
    @contract.signature_parameters = Ades::SignatureParameters.new
  end

  def create
    # TODO check agree_to_policies

    @contract = Contract.new_from_ui(contract_params)
    @contract.user = current_user

    # Set user and uuid for any documents
    @contract.documents.each do |document|
      document.user = @current_user
      document.uuid = SecureRandom.uuid
    end

    if @contract.save
      redirect_to edit_contract_path(@contract)
    else
      # Ensure signature_parameters is initialized for form re-rendering
      @contract.signature_parameters ||= Ades::SignatureParameters.new
      render :new, status: :unprocessable_entity
    end
  end

  def show
    respond_to do |format|
      format.html # renders show.html.erb
      format.json do
        # Provide contract data for signing
        render json: {
          id: @contract.id,
          uuid: @contract.uuid,
          documents: @contract.documents.map do |doc|
            {
              id: doc.id,
              filename: doc.filename,
              content_type: doc.blob.content_type,
              download_url: rails_blob_url(doc.blob),
              xdc_parameters: doc.xdc_parameters ? {
                auto_load_eform: doc.xdc_parameters.auto_load_eform,
                container_xmlns: doc.xdc_parameters.container_xmlns,
                embed_used_schemas: doc.xdc_parameters.embed_used_schemas,
                fs_form_identifier: doc.xdc_parameters.fs_form_identifier,
                identifier: doc.xdc_parameters.identifier,
                schema: doc.xdc_parameters.schema,
                schema_identifier: doc.xdc_parameters.schema_identifier,
                schema_mime_type: doc.xdc_parameters.schema_mime_type,
                transformation: doc.xdc_parameters.transformation,
                transformation_identifier: doc.xdc_parameters.transformation_identifier,
                transformation_language: doc.xdc_parameters.transformation_language,
                transformation_media_destination_type_description: doc.xdc_parameters.transformation_media_destination_type_description,
                transformation_target_environment: doc.xdc_parameters.transformation_target_environment
              } : nil
            }
          end,
          allowed_methods: @contract.allowed_methods,
          signature_parameters: @contract.signature_parameters
        }
      end
    end
  end

  def sign
    @contract.accept_signed_file(signed_document_param)

    respond_to do |format|
      format.html {
        flash[:notice] = "The contract was successfully signed."
        redirect_to @contract
      }
      format.json { render json: { success: true, message: "The contract was successfully signed." } }
    end
  end

  def sign_avm
    if @contract.has_active_avm_session?
      existing_session = @contract.current_avm_session
      avm_url = existing_session.avm_url

      respond_to do |format|
        format.turbo_stream do
          # Determine cancel URL based on referrer context
          cancel_url = if request.referrer&.include?("/iframe")
            iframe_params = {}
            iframe_params[:no_preview] = true if params[:no_preview].present?
            iframe_contract_path(@contract, iframe_params)
          else
            contract_path(@contract)
          end

          render turbo_stream: turbo_stream.replace(
            "signature_actions_#{@contract.uuid}",
            partial: "contracts/avm_signing_pending",
            locals: {
              contract: @contract,
              avm_session: existing_session,
              avm_url: avm_url,
              cancel_url: cancel_url
            }
          )
        end
      end
      return
    end

    result = AutogramEnvironment.avm_service.initiate_signing(@contract)
    avm_session = @contract.avm_sessions.create!(
      document_id: result[:document_id],
      encryption_key: result[:encryption_key],
      signing_started_at: result[:signing_started_at],
      status: "pending"
    )

    AvmSigningPollJob.perform_later(avm_session)

    respond_to do |format|
      format.turbo_stream do
        # Determine cancel URL based on referrer context
        cancel_url = if request.referrer&.include?("/iframe")
          iframe_params = {}
          iframe_params[:no_preview] = true if params[:no_preview].present?
          iframe_contract_path(@contract, iframe_params)
        else
          contract_path(@contract)
        end

        render turbo_stream: turbo_stream.replace(
          "signature_actions_#{@contract.uuid}",
          partial: "contracts/avm_signing_pending",
          locals: {
            contract: @contract,
            avm_session: avm_session,
            avm_url: avm_session.avm_url,
            cancel_url: cancel_url
          }
        )
      end
    end
  rescue => e
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "signature_actions_#{@contract.uuid}",
          partial: "contracts/signature_error",
          locals: { contract: @contract, error: e.message }
        )
      end
    end
  end

  def signed_document
    redirect_to rails_blob_url(@contract.signed_document, disposition: "attachment"), allow_other_host: true
  end

  def validate
    document_to_validate = if @contract.signed_document.attached?
      temp_doc = Document.new(user: @contract.user, uuid: SecureRandom.uuid)
      temp_doc.blob.attach(@contract.signed_document.blob)
      temp_doc
    elsif @contract.documents.size == 1
      @contract.documents.first
    else
      nil
    end

    if document_to_validate.nil?
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
      validation_result = AutogramEnvironment.autogram_service.validate_signatures(document_to_validate)

      respond_to do |format|
        format.html do
          @validation_result = validation_result
          @document = document_to_validate
          render "validate"
        end
        format.json do
          signatures = validation_result.signatures.flatten

          render json: {
            hasSignatures: validation_result.has_signatures,
            signatures: signatures.map { |sig| format_signature_for_json(sig) },
            documentInfo: validation_result.document_info,
            errors: validation_result.errors
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

  def edit
  end

  def destroy
    @contract.destroy!
    redirect_to contracts_path, notice: "The contract and all its documents were successfully deleted."
  rescue StandardError => e
    redirect_to contract_path(@contract), alert: "An error occurred while deleting the contract: #{e.message}"
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

  def set_contract
    @contract = current_user.contracts.find_by!(uuid: params[:id])
  end

  def contract_params
    params.require(:contract).permit(:uuid, documents_attributes: [ :blob, :_destroy ], signature_parameters_attributes: [ :format_container_combination, :add_content_timestamp ])
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
            authority: ts[:authority],
            qualification: ts[:qualification]
          }
        end
      } : nil
    }
  end
end
