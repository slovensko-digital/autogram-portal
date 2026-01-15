class DocumentsController < ApplicationController
  before_action :set_document, except: [ :index, :new, :create ]
  before_action :allow_iframe, only: [ :pdf_preview ]

  def index
    @documents = current_user.documents.includes(:user).order(created_at: :desc)
  end

  def new
    @document = Document.new
  end

  def create
    @document = Document.new(document_params)
    @document.user = current_user
    @document.uuid = SecureRandom.uuid

    if @document.save
      redirect_to document_path(@document)
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
    visualization_result = @document.visualize
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

  def download
    if @document.blob.attached?
      redirect_to rails_blob_path(@document.blob, disposition: "attachment"), allow_other_host: false
    else
      redirect_to document_path(@document), alert: t("documents.alerts.no_file_attached")
    end
  end

  def signature_parameters
    render partial: "signature_parameters"
  end

  def create_contract_from_document
    return redirect_to document_path(@document), alert: t("documents.alerts.already_part_of_contract") if @document.contract.present?

    ActiveRecord::Base.transaction do
      contract = Contract.create!(
        user: current_user,
        allowed_methods: [ params[:allowed_method] ],
        signature_parameters_attributes: { combined_format: params[:format_container_combination] },
        documents: [ @document ]
      )

      @document.update!(contract: contract)
      redirect_to contract_path(contract)
    end
  rescue ActiveRecord::RecordInvalid
    error_messages = []
    error_messages.concat(contract.errors.full_messages) if contract.errors.any?
    error_messages.concat(@document.errors.full_messages) if @document.errors.any?

    redirect_to document_path(@document), alert: t("documents.alerts.failed_to_create_contract", errors: error_messages.join(", "))
  end

  def signature_extension
    render partial: "signature_extension"
  end

  def extend_signatures
    return head :unauthorized unless current_user
    return redirect_to document_path(@document), alert: t("documents.alerts.already_part_of_contract") if @document.contract.present?
    return redirect_to document_path(@document), alert: t("documents.alerts.all_signatures_have_timestamps") unless @document.extendable_signatures?

    begin
      @document.extend_signatures!
      redirect_to document_path(@document), notice: t("documents.alerts.signature_extended_successfully")
    rescue => e
      redirect_to document_path(@document), alert: t("documents.alerts.failed_to_extend_signatures", error: e.message)
    end
  end

  private

  def set_document
    @document = Document.find_by(uuid: params[:id]) || Document.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:blob)
  end
end
