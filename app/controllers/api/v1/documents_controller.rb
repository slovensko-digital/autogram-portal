class Api::V1::DocumentsController < ApiController
  before_action :set_document, only: [ :show ]
  after_action :verify_policy_scoped

  def show
    if @document&.blob&.attached?
      render partial: "api/v1/documents/document", locals: { document: @document }
    else
      render json: { error: "Document not found" }, status: :not_found
    end
  end

  private

  def set_document
    @document = policy_scope([ :api, :v1, Document ]).find_by(uuid: params[:id])
    if @document
      authorize [ :api, :v1, @document ]
    else
      render json: { error: "Document not found" }, status: :not_found
    end
  end
end
