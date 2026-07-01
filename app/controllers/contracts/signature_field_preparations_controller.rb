module Contracts
  class SignatureFieldPreparationsController < ApplicationController
    before_action :set_contract
    before_action :ensure_author_can_prepare_fields
    before_action :set_signature_field_preparation, only: :destroy
    before_action :load_collections

    def index
      @signature_field_preparation = build_signature_field_preparation
    end

    def create
      @signature_field_preparation = @contract.signature_field_preparations.build(signature_field_preparation_attributes)

      if @signature_field_preparation.save
        @contract.replace_prepared_signature_field_content_versions!
        flash.now[:notice] = t("contracts.signature_field_preparations.create.success")
        load_collections
        @signature_field_preparation = build_signature_field_preparation
        render :index
      else
        flash.now[:alert] = @signature_field_preparation.errors.full_messages.to_sentence
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      @signature_field_preparation.destroy!
      @contract.replace_prepared_signature_field_content_versions!
      flash.now[:notice] = t("contracts.signature_field_preparations.destroy.success")
      load_collections
      @signature_field_preparation = build_signature_field_preparation

      render :index
    end

    def finalize
      if @signature_field_preparations.blank?
        return redirect_to bundle_path(@contract.bundle), alert: t("contracts.signature_field_preparations.finalize.empty")
      end

      document = @contract.documents_to_sign.first
      prepared_content = AutogramEnvironment.autogram_service.prepare_signature_fields(document, fields: signature_field_payloads)

      @contract.add_prepared_signature_fields_content_version!(
        content: prepared_content,
        filename: prepared_signature_fields_filename(document),
        content_type: document.content_type
      )

      redirect_to bundle_path(@contract.bundle), notice: t("contracts.signature_field_preparations.finalize.success")
    rescue AutogramService::ServiceUnavailableError
      redirect_to bundle_path(@contract.bundle), alert: t("contracts.signature_field_preparations.finalize.failure")
    end

    private

    def set_contract
      @contract = Contract.find_by!(uuid: params[:contract_id])
    end

    def ensure_author_can_prepare_fields
      return head :forbidden unless current_user.present? && @contract.bundle&.author == current_user
      return if @contract.pades_field_preparation_allowed?

      head :unprocessable_entity
    end

    def set_signature_field_preparation
      @signature_field_preparation = @contract.signature_field_preparations.find(params[:id])
    end

    def load_collections
      @documents = @contract.documents.select(&:is_pdf?)
      @preview_document = @contract.documents_to_sign.first
      @signature_field_preparations = @contract.signature_field_preparations.includes(:document, :recipient).order(:created_at)
      assigned_recipient_ids = @signature_field_preparations.map(&:recipient_id)
      @recipients = @contract.bundle.active_recipients.awaiting_contract(@contract).where.not(id: assigned_recipient_ids).order(:created_at)
    end

    def build_signature_field_preparation
      @contract.signature_field_preparations.build(
        page: 1,
        x: 36,
        y: 36,
        width: 180,
        height: 64,
        document: @documents.first,
        recipient: @recipients.first
      )
    end

    def signature_field_payloads
      @signature_field_preparations.map do |preparation|
        {
          "fieldName" => preparation.field_identifier,
          page: preparation.page,
          x: preparation.x.to_f,
          y: preparation.y.to_f,
          width: preparation.width.to_f,
          height: preparation.height.to_f
        }
      end
    end

    def prepared_signature_fields_filename(document)
      "#{File.basename(document.filename, '.*')}-prepared-fields.pdf"
    end

    def signature_field_preparation_attributes
      preparation_params = params.require(:signature_field_preparation).permit(:document_uuid, :recipient_uuid, :page, :x, :y, :width, :height)

      {
        document: @contract.documents.find_by!(uuid: preparation_params[:document_uuid]),
        recipient: @contract.bundle.active_recipients.find_by!(uuid: preparation_params[:recipient_uuid]),
        page: preparation_params[:page],
        x: preparation_params[:x],
        y: preparation_params[:y],
        width: preparation_params[:width],
        height: preparation_params[:height]
      }
    end
  end
end
