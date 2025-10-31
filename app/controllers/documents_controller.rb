class DocumentsController < ApplicationController
  before_action :set_document, except: [ :index, :new, :create ]
  before_action :allow_iframe, only: [ :pdf_preview ]

  def index
    @documents = Document.includes(:user).order(created_at: :desc)
  end

  def new
    @document = Document.new
  end

  def create
    @document = Document.new(document_params)
    @document.user = current_user
    @document.uuid = SecureRandom.uuid

    if @document.save
      redirect_to document_path(@document), notice: "Document was successfully uploaded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  def actions
    render partial: "actions", locals: { document: @document }
  rescue StandardError => e
    render partial: "actions_error", locals: { error: e.message }
  end

  def validate
      @validation_result = @document.validation_result
  rescue StandardError => e
    respond_to do |format|
      format.html do
        render "validate_error", locals: { errors: [ e.message ] }
      end
      format.json do
        render json: { errors: [ e.message ] }, status: :unprocessable_entity
      end
    end
  end

  def visualize
    @visualization_result = @document.visualize
    if @visualization_result.is_a?(Hash) && !@visualization_result[:content].nil?
      render "visualize", locals: { result: @visualization_result }
    else
      render "visualize_error", locals: { errors: @visualization_result.errors }
    end
  end

  def pdf_preview
    visualization_result = AutogramEnvironment.autogram_service.visualize_document(@document)
    if visualization_result.is_a?(Hash) && visualization_result[:mime_type]&.include?("application/pdf")
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
  rescue StandardError
    head :unprocessable_entity
  end

  def create_contract_from_document
    if @document.contract.present?
      redirect_to document_path(@document), alert: "This document is already part of a contract."
      return
    end

    @contract = Contract.new
    @contract.user = current_user
    @contract.uuid = SecureRandom.uuid

    allowed_method = params[:allowed_method]
    if allowed_method.in?([ "qes", "ts-qes" ])
      @contract.allowed_methods = [ allowed_method ]
    else
      @contract.allowed_methods = [ "qes" ]
    end

    @contract.build_signature_parameters
    format_container_combination = params[:format_container_combination]
    if format_container_combination.in?([ "PADES", "XADES_ASICE", "CADES_ASICE" ])
      @contract.signature_parameters.format_container_combination = format_container_combination
    else
      @contract.signature_parameters.format_container_combination = "PADES"
    end

    @contract.documents << @document
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

  def extend_signatures
    return head :unauthorized unless current_user
    return redirect_to document_path(@document), alert: "This document is already part of a contract." if @document.contract.present?
    return redirect_to document_path(@document), alert: "All signatures already have qualified timestamps." unless @document.extendable_signatures?

    # TODO: extend signatures implementation
  end

  private

  def set_document
    @document = Document.find_by(uuid: params[:id]) || Document.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:blob)
  end
end
