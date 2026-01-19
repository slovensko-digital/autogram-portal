class DocumentsController < ApplicationController
  before_action :set_document
  before_action :allow_iframe, only: [ :pdf_preview ]

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
      render status: :not_found, alert: t("documents.alerts.no_file_attached")
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
