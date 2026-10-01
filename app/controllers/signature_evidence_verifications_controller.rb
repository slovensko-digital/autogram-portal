class SignatureEvidenceVerificationsController < ApplicationController
  # Public evidence is looked up by its public reference.
  before_action :skip_authorization, only: [ :show, :download ]

  rescue_from Pundit::NotAuthorizedError, with: -> { head :forbidden }

  def show
    @reference = params[:reference].to_s.strip
    return if @reference.blank?

    @signature_evidence_record = find_signature_evidence_record(@reference)
    @lookup_error = t(".not_found") if @signature_evidence_record.blank?
  end

  def download
    @reference = params[:reference].to_s.strip
    @signature_evidence_record = find_signature_evidence_record(@reference)
    return head :not_found if @signature_evidence_record.blank?

    if @signature_evidence_record.sealed_evidence.attached?
      redirect_to rails_blob_path(@signature_evidence_record.sealed_evidence, disposition: "attachment"), allow_other_host: false
    elsif @signature_evidence_record.signed_manifest.present?
      send_data @signature_evidence_record.signed_manifest,
                type: "application/json",
                disposition: "attachment",
                filename: "signature-evidence-#{@signature_evidence_record.public_reference}.json"
    else
      head :not_found
    end
  end

  def download_private
    @reference = params[:reference].to_s.strip
    @signature_evidence_record = find_signature_evidence_record(@reference)
    if @signature_evidence_record.blank?
      skip_authorization
      return head :not_found
    end
    authorize @signature_evidence_record
    return head :not_found unless @signature_evidence_record.private_evidence_package.attached?

    send_data @signature_evidence_record.private_evidence_package.download,
              type: @signature_evidence_record.private_evidence_package.content_type,
              disposition: "attachment",
              filename: @signature_evidence_record.private_evidence_package.filename.to_s
  end

  private

  def find_signature_evidence_record(reference)
    SignatureEvidenceRecord.includes(:contract_content_version).find_by(public_reference: reference)
  end
end
