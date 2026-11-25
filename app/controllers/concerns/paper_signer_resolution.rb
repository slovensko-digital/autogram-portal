# Who signs a contract on paper: the contract by its UUID, the active recipient of the signing link
# (params[:recipient]) within that contract and the recipient's signer contract. Unknown and withdrawn
# recipients get 404. A recipient whose signature is no longer needed, already made or declined, or
# who cannot sign this contract on paper (any more) returns to the signing page.
#
# The phone link (params[:token], PaperSignatureAccessToken) opens one paper signature and its recipient
# instead, for its pages and submitting it while it is a draft the recipient can still sign on paper.
# Otherwise it answers 410 with the link_expired page, never a redirect to the recipient's signing link.
# A token of another contract gets 404 and discarding the scan with it 403.
module PaperSignerResolution
  extend ActiveSupport::Concern

  included do
    before_action :set_paper_signer
    before_action :ensure_paper_signing_open
    helper_method :paper_signer_link_params, :phone_link?
  end

  private

  def set_paper_signer
    @contract = Contract.includes(:bundle).find_by!(uuid: params[:contract_id])

    if phone_link?
      @phone_paper_signature = PaperSignatureAccessToken.verify(params[:token])
      return render_phone_link_expired unless @phone_paper_signature
      raise ActiveRecord::RecordNotFound unless @phone_paper_signature.contract == @contract

      @signer_contract = @phone_paper_signature.signer_contract
      @recipient = @signer_contract.recipient
    else
      @recipient = @contract.recipients.active.find_by!(uuid: params[:recipient].to_s)
    end

    authorize [ :signing, SigningBundleAccess.new(bundle: @contract.bundle, recipient: @recipient) ], :paper_sign?
    @signer_contract ||= @recipient.signer_contracts.find_by!(contract: @contract)
  end

  def ensure_paper_signing_open
    return ensure_phone_link_open if phone_link?

    if @signer_contract.superseded?
      redirect_to sign_bundle_path(@contract.bundle, recipient: @recipient.uuid, iframe: params[:iframe]),
                  notice: t("bundles.sign.signature_no_longer_required")
    elsif !@signer_contract.awaiting? || (!paper_signing_available? && !discarding?)
      redirect_to helpers.signing_page_path(@contract, recipient: @recipient, iframe: params[:iframe])
    elsif !discarding? && sign_limit_reached?
      render_sign_limit_reached
    end
  end

  # The phone adds pages to its draft and submits it; discarding the scan stays with the signing link.
  def ensure_phone_link_open
    if discarding_paper_signature?
      head :forbidden
    elsif !phone_link_open?
      render_phone_link_expired
    elsif sign_limit_reached?
      render_sign_limit_reached
    end
  end

  def phone_link_open?
    @phone_paper_signature.draft? && @recipient.active? && @signer_contract.awaiting? && paper_signing_available?
  end

  # Requests from the phone carry the token instead of the recipient.
  def phone_link?
    params[:token].present?
  end

  def paper_signing_available?
    @contract.paper_signing_available_for?(@recipient, embedded: params[:iframe].present?)
  end

  def sign_limit_reached?
    @contract.signature_request_limit_reached_for?(@recipient.user)
  end

  def render_sign_limit_reached
    render "bundles/sign_limit_reached", locals: { sender: @contract.tenant.sender_display_name }, status: :forbidden
  end

  # 410 for an expired or invalid phone link and one whose paper signature is no longer a draft; for a
  # submitted one the page confirms the submission instead (made on the phone or meanwhile on the computer).
  def render_phone_link_expired
    render "contracts/paper_signatures/link_expired", status: :gone, locals: { paper_signature: @phone_paper_signature }
  end

  # Discarding a scan or one of its pages stays possible when paper signing is no longer offered.
  def discarding?
    action_name == "destroy"
  end

  # Discarding the whole draft or scan, not one of its pages.
  def discarding_paper_signature?
    false
  end

  # The paper signature the request works on: the draft of the phone link, otherwise the recipient's
  # open one, with open_draft: a new draft when none is open.
  def current_paper_signature(open_draft: false)
    return @phone_paper_signature if phone_link?

    open_draft ? PaperSignature.open_for!(@signer_contract) : @signer_contract.paper_signatures.open.first
  end

  # What identifies the signer in the links of the paper signing page and its pages. The phone link
  # keeps its token, and with it its expiry, and never leads to the recipient's signing link.
  def paper_signer_link_params
    phone_link? ? { token: params[:token] } : { recipient: @recipient.uuid }
  end

  def paper_signature_page_path
    contract_paper_signature_path(@contract, **paper_signer_link_params)
  end
end
