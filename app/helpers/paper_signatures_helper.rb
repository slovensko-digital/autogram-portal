module PaperSignaturesHelper
  # The paper signature that takes the place of the signing method choice on the signing page: a scan
  # awaiting review or a draft with pages. The paper signing page opens a draft before anything is
  # uploaded, so an empty draft leaves the choice in place.
  def paper_signature_in_progress(contract, recipient)
    @paper_signatures_in_progress ||= {}
    key = [ contract.id, recipient&.id ]
    return @paper_signatures_in_progress[key] if @paper_signatures_in_progress.key?(key)

    paper_signature = paper_signer_contract(contract, recipient)&.paper_signatures&.open&.first
    paper_signature = nil if paper_signature&.draft? && paper_signature.pages.none?
    @paper_signatures_in_progress[key] = paper_signature
  end

  # The scan the sender returned, unless the recipient discarded or replaced it since.
  def returned_paper_signature(signer_contract)
    return unless signer_contract

    latest = signer_contract.paper_signatures.where.not(status: PaperSignature::OPEN_STATUSES).order(:id).last
    latest if latest&.returned?
  end

  def paper_signer_contract(contract, recipient)
    recipient&.signer_contracts&.find_by(contract: contract)
  end

  def paper_signature_submitted_message(paper_signature)
    sender = paper_signature.contract.tenant.sender_display_name
    email = paper_signature.recipient&.email

    if email.present?
      t("paper_signatures.submitted.message", sender: sender, email: email)
    else
      t("paper_signatures.submitted.message_without_email", sender: sender)
    end
  end

  # Members of the sending organization are named only by their name, otherwise by the organization.
  def paper_signature_reviewer_name(paper_signature)
    paper_signature.reviewed_by&.name.presence || paper_signature.contract.tenant.sender_display_name
  end
end
