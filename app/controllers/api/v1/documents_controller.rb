class Api::V1::DocumentsController < ApiController
  before_action :set_document, only: [ :show ]

  def show
    if @document&.blob&.attached?
      render partial: "api/v1/documents/document", locals: { document: @document }
    else
      render json: { error: "Document not found" }, status: :not_found
    end
  end

  private

  def set_document
    @document = accessible_documents.find_by(uuid: params[:id])
    render json: { error: "Document not found" }, status: :not_found unless @document
  end

  def accessible_documents
    Document
      .joins(:contract)
      .left_outer_joins(contract: :bundle)
      .where("contracts.user_id = :user_id OR bundles.user_id = :user_id", user_id: current_user.id)
  end
end
