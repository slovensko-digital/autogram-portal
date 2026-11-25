# Who signs a contract on paper: the contract by its UUID, the active recipient of the signing link
# (params[:recipient]) within that contract and the recipient's signer contract. Unknown and withdrawn
# recipients get 404. A recipient whose signature is no longer needed, already made or declined, or
# who cannot sign this contract on paper (any more) returns to the signing page.
module PaperSignerResolution
  extend ActiveSupport::Concern

  included do
    before_action :set_paper_signer
    before_action :ensure_paper_signing_open
    helper_method :paper_signer_link_params
  end

  private

  def set_paper_signer
    @contract = Contract.includes(:bundle).find_by!(uuid: params[:contract_id])
    @recipient = @contract.recipients.active.find_by!(uuid: params[:recipient].to_s)
    authorize [ :signing, SigningBundleAccess.new(bundle: @contract.bundle, recipient: @recipient) ], :paper_sign?
    @signer_contract = @recipient.signer_contracts.find_by!(contract: @contract)
  end

  def ensure_paper_signing_open
    if @signer_contract.superseded?
      redirect_to sign_bundle_path(@contract.bundle, recipient: @recipient.uuid, iframe: params[:iframe]),
                  notice: t("bundles.sign.signature_no_longer_required")
    elsif !@signer_contract.awaiting? || (!paper_signing_available? && !discarding?)
      redirect_to helpers.signing_page_path(@contract, recipient: @recipient, iframe: params[:iframe])
    elsif !discarding? && @contract.signature_request_limit_reached_for?(@recipient.user)
      render "bundles/sign_limit_reached", locals: { sender: @contract.tenant.sender_display_name }, status: :forbidden
    end
  end

  def paper_signing_available?
    @contract.paper_signing_available_for?(@recipient, embedded: params[:iframe].present?)
  end

  # Discarding a scan or one of its pages stays possible when paper signing is no longer offered.
  def discarding?
    action_name == "destroy"
  end

  # What identifies the signer in the links of the paper signing page and its pages.
  def paper_signer_link_params
    { recipient: @recipient.uuid }
  end

  def paper_signature_page_path
    contract_paper_signature_path(@contract, **paper_signer_link_params)
  end
end
