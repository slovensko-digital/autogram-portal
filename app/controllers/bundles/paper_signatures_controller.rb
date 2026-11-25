# Members of the organization that sent the bundle review the scan of a document a recipient signed
# on paper: they compare it with the original and approve it, which completes the signature, or return
# it with a reason. The scan is served only here, never through a blob link.
class Bundles::PaperSignaturesController < ApplicationController
  before_action :set_bundle
  before_action :set_paper_signature

  rescue_from Pundit::NotAuthorizedError, with: :render_tenant_record_denial
  rescue_from PaperSignature::NoLongerReviewable, with: :redirect_no_longer_reviewable

  def show
    redirect_no_longer_reviewable unless @paper_signature.reviewable?
  end

  def approve
    @paper_signature.approve!(current_user)
    redirect_to bundle_path(@bundle), notice: t("paper_signatures.review.approved"), status: :see_other
  end

  def return_scan
    @paper_signature.return!(current_user, params[:return_reason].to_s.strip)
    redirect_to bundle_path(@bundle), notice: t("paper_signatures.review.returned"), status: :see_other
  rescue ActiveRecord::RecordInvalid => e
    redirect_to bundle_paper_signature_path(@bundle, @paper_signature), alert: e.record.errors.full_messages.to_sentence, status: :see_other
  end

  # The scan awaiting review or approved; the signer's discarded or returned scans stay history.
  def scan
    raise ActiveRecord::RecordNotFound unless (@paper_signature.submitted? || @paper_signature.approved?) && @paper_signature.scan.attached?

    send_data @paper_signature.scan.download,
      filename: @paper_signature.scan.filename.to_s,
      type: PaperScan::PDF_TYPE,
      disposition: params[:disposition] == "inline" ? "inline" : "attachment"
  end

  private

  def set_bundle
    @bundle = Bundle.find_by_uuid!(params[:bundle_id])
    authorize @bundle, :review_paper_signatures?
  end

  def set_paper_signature
    @paper_signature = @bundle.paper_signatures.find_by!(uuid: params[:uuid])
  end

  def redirect_no_longer_reviewable
    redirect_to bundle_path(@bundle), notice: t("bundles.sign.signature_no_longer_required"), status: :see_other
  end
end
