class DocumentsController < ApplicationController
  before_action :set_document, only: [ :show, :validate, :visualize ]

  def create
    @document = Document.new

    @document.user = @user
    @document.uuid = SecureRandom.uuid
    @document.blob.attach(params[:document][:file])

    if @document.save
      redirect_to document_path(@document)
    else
      redirect_to root_path, alert: "Failed to upload file"
    end
  end

  def show
  end

  def validate
    validation_result = AutogramEnvironment.autogram_service.validate_signatures(@document)

    # Flatten signatures in case they're nested in arrays
    signatures = validation_result.signatures.flatten

    render json: {
      hasSignatures: validation_result.has_signatures,
      signatures: signatures.map { |sig| format_signature_for_json(sig) },
      documentInfo: validation_result.document_info,
      errors: validation_result.errors
    }
  end

  def visualize
    visualization_result = AutogramEnvironment.autogram_service.visualize_document(@document)

    if visualization_result.is_a?(Hash) && !visualization_result[:content].nil?
      # Success - return visualization data
      render json: {
        content: visualization_result[:content],
        mimeType: visualization_result[:mime_type],
        filename: visualization_result[:filename]
      }
    else
      # Error - result is a ValidationResult with errors
      render json: {
        errors: visualization_result.errors
      }, status: :unprocessable_entity
    end
  end

  private

  def set_document
    @document = Document.find(params[:id])
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
