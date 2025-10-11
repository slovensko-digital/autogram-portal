class DocumentsController < ApplicationController
  before_action :set_document, only: [ :show, :validate, :visualize, :pdf_preview, :create_contract_from_document ]
  before_action :allow_iframe, only: [ :pdf_preview ]

  def index
    @documents = Document.includes(:user).order(created_at: :desc)
  end

  def new
    @document = Document.new
  end

  def create
    @document = Document.new(document_params)
    @document.user = @current_user
    @document.uuid = SecureRandom.uuid

    if @document.save
      redirect_to document_path(@document), notice: "Document was successfully uploaded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    respond_to do |format|
      format.html # renders show.html.erb
      format.json do
        # Provide document data for viewing
        render json: {
          id: @document.id,
          filename: @document.filename,
          content_type: @document.blob.content_type,
          download_url: rails_blob_url(@document.blob),
          contract_id: @document.contract_id
        }
      end
    end
  end

  def validate
    begin
      validation_result = AutogramEnvironment.autogram_service.validate_signatures(@document)

      respond_to do |format|
        format.html do
          @validation_result = validation_result
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

  def visualize
    visualization_result = @document.visualize

    respond_to do |format|
      format.html do
        if visualization_result.is_a?(Hash) && !visualization_result[:content].nil?
          @visualization_result = visualization_result
          render "visualize", locals: { result: visualization_result }
        else
          render "visualize_error", locals: { errors: visualization_result.errors }
        end
      end
    end
  end

  def pdf_preview
    visualization_result = AutogramEnvironment.autogram_service.visualize_document(@document)

    if visualization_result.is_a?(Hash) && visualization_result[:mime_type]&.include?("application/pdf")
      # Decode base64 content and serve as PDF
      pdf_content = Base64.strict_decode64(visualization_result[:content])

      respond_to do |format|
        format.pdf do
          send_data pdf_content,
                   type: "application/pdf",
                   disposition: "inline",
                   filename: "#{@document.filename}_preview.pdf"
        end
      end
    else
      head :not_found
    end
  rescue => e
    Rails.logger.error "PDF preview error: #{e.message}"
    head :unprocessable_entity
  end

  def create_contract_from_document
    # Check if document already belongs to a contract
    if @document.contract.present?
      redirect_to document_path(@document), alert: "This document is already part of a contract."
      return
    end

    # Create a new contract
    @contract = Contract.new
    @contract.user = @current_user
    @contract.uuid = SecureRandom.uuid

    # Set allowed methods based on the radio button selection
    allowed_method = params[:allowed_method]
    if allowed_method.in?([ "qes", "ts-qes" ])
      @contract.allowed_methods = [ allowed_method ]
    else
      @contract.allowed_methods = [ "qes" ] # default fallback
    end

    # Create signature parameters
    @contract.build_signature_parameters
    format_container_combination = params[:format_container_combination]
    if format_container_combination.in?([ "PADES", "XADES_ASICE", "CADES_ASICE" ])
      @contract.signature_parameters.format_container_combination = format_container_combination
    else
      @contract.signature_parameters.format_container_combination = "PADES" # default fallback
    end

    # Associate the document with the contract before saving
    @contract.documents << @document

    # Use a transaction to ensure both saves succeed or both fail
    ActiveRecord::Base.transaction do
      if @contract.save!
        @document.update!(contract: @contract)
        redirect_to contract_path(@contract), notice: "Contract was successfully created from document."
      end
    end
  rescue ActiveRecord::RecordInvalid
    error_messages = []
    error_messages.concat(@contract.errors.full_messages) if @contract.errors.any?
    error_messages.concat(@document.errors.full_messages) if @document.errors.any?

    redirect_to document_path(@document), alert: "Failed to create contract: #{error_messages.join(', ')}"
  end

  private

  def set_document
    # Find by UUID first, fallback to ID for backward compatibility during transition
    @document = Document.find_by(uuid: params[:id]) || Document.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:blob)
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
