module PaperSignaturesHelper
  # Classes of the file inputs on the desktop and phone upload forms.
  PAPER_FILE_INPUT_CLASSES = "block w-full min-w-0 text-sm text-gray-700 file:mr-3 file:rounded-md file:border-0 file:bg-white file:px-3 file:py-2 file:text-sm file:font-semibold file:text-gray-900 file:ring-1 file:ring-gray-500 file:ring-inset hover:file:bg-gray-50".freeze

  def paper_file_input_classes
    PAPER_FILE_INPUT_CLASSES
  end

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

  # The phone link in the QR code of the paper signing page, with a new token on every render.
  def paper_signature_phone_url(contract, paper_signature)
    contract_paper_signature_url(contract, token: PaperSignatureAccessToken.generate(paper_signature))
  end

  # Members of the sending organization are named only by their name, otherwise by the organization.
  def paper_signature_reviewer_name(paper_signature)
    paper_signature.reviewed_by&.name.presence || paper_signature.contract.tenant.sender_display_name
  end

  # The reviewer as the organization's members know them: name or email.
  def paper_signature_approver_name(paper_signature)
    reviewer = paper_signature.reviewed_by
    reviewer&.name.presence || reviewer&.email || paper_signature.contract.tenant.sender_display_name
  end

  # Scans the organization has yet to review, oldest first.
  def paper_signatures_awaiting_review(bundle)
    bundle.paper_signatures.submitted
      .includes(signer_contract: [ { signer: :recipient }, { contract: { documents: { blob_attachment: :blob } } } ])
      .order(:submitted_at)
      .select(&:reviewable?)
  end

  # Submitted and approved paper signatures of the bundle by recipient id, for the recipient cards.
  def submitted_and_approved_paper_signatures_by_recipient(bundle)
    bundle.paper_signatures
      .where(status: %w[submitted approved])
      .includes(:reviewed_by, signer_contract: [ :signer, { contract: { documents: { blob_attachment: :blob } } } ])
      .order(:submitted_at)
      .group_by { |paper_signature| paper_signature.signer.recipient_id }
  end

  # The document the scan is compared with on the review page, as the bundle detail shows it.
  def paper_signature_original_file(contract)
    if contract.source_document_attached? && contract.source_document_is_pdf?
      contract.latest_source_content_version.file
    else
      contract.documents.first&.blob
    end
  end

  def paper_signature_time_tag(time)
    tag.time(time.in_time_zone("Europe/Bratislava").strftime("%-d. %-m. %Y %H:%M"), datetime: time.iso8601)
  end
end
