# == Schema Information
#
# Table name: paper_signatures
#
#  id                 :bigint           not null, primary key
#  return_reason      :text
#  reviewed_at        :datetime
#  status             :string           default("draft"), not null
#  submitted_at       :datetime
#  uuid               :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  reviewed_by_id     :bigint
#  signer_contract_id :bigint           not null
#
# Indexes
#
#  index_paper_signatures_on_open_signer_contract_id  (signer_contract_id) UNIQUE WHERE ((status)::text = ANY (ARRAY[('draft'::character varying)::text, ('submitted'::character varying)::text]))
#  index_paper_signatures_on_reviewed_by_id           (reviewed_by_id)
#  index_paper_signatures_on_signer_contract_id       (signer_contract_id)
#  index_paper_signatures_on_uuid                     (uuid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (reviewed_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (signer_contract_id => signer_contracts.id)
#
# A signature made on paper: the signer prints the document, signs it by hand and uploads photos of
# the pages or a PDF scan (collected as pages of a draft), then submits them as one PDF scan. A member
# of the sending organization approves it, which completes the signature, or returns it with a reason.
# Returned and canceled attempts are kept as history; only one per signer contract is open at a time.
class PaperSignature < ApplicationRecord
  # The upload cannot become (part of) a scan; the message tells the signer what to upload instead.
  class InvalidUpload < StandardError
    attr_reader :reason

    def initialize(reason, **interpolations)
      @reason = reason
      super(I18n.t(reason, scope: "paper_signatures.errors", **interpolations))
    end
  end

  # The scan is not awaiting review any more, or its signature is no longer needed (signed another
  # way, superseded, declined or withdrawn).
  class NoLongerReviewable < StandardError; end

  OPEN_STATUSES = %w[draft submitted].freeze
  # Anyone with the signing link uploads into the sender's storage, so a draft is capped. Phones send
  # photos downsized by the browser, so the caps are far above a real scan.
  MAX_PAGES = 50
  MAX_FILE_BYTES = 25.megabytes

  belongs_to :signer_contract
  belongs_to :reviewed_by, class_name: "User", optional: true
  has_many :pages, -> { order(:position) }, class_name: "PaperSignaturePage", dependent: :destroy, inverse_of: :paper_signature
  has_one_attached :scan

  delegate :contract, :signer, :recipient, to: :signer_contract

  enum :status, { draft: "draft", submitted: "submitted", approved: "approved", returned: "returned", canceled: "canceled" }

  validates :return_reason, presence: true, if: :returned?

  before_validation :ensure_uuid, on: :create

  scope :open, -> { where(status: OPEN_STATUSES) }

  # The open paper signature of the signer contract, or a new draft.
  def self.open_for!(signer_contract)
    signer_contract.paper_signatures.open.first || transaction(requires_new: true) { signer_contract.paper_signatures.create! }
  rescue ActiveRecord::RecordNotUnique
    signer_contract.paper_signatures.open.first!
  end

  def to_param
    uuid
  end

  def open?
    OPEN_STATUSES.include?(status)
  end

  # The scan awaits review and the signature is still needed (not signed another way, superseded,
  # declined or withdrawn).
  def reviewable?
    submitted? && signer_contract.awaiting?
  end

  # Adds photos (JPEG, PNG) after the current pages, or one PDF, which replaces all pages; photos
  # replace an uploaded PDF in turn. The type is read from the content, not from what the browser
  # declares. At most MAX_PAGES pages of at most MAX_FILE_BYTES each. Returns the new pages; none
  # when the paper signature is no longer a draft (e.g. the phone uploads after the computer submitted).
  def add_pages!(files)
    files = Array(files).select { |file| file.respond_to?(:read) }
    raise too_many_pages if files.size > MAX_PAGES

    uploads = files.map { |file| identify_upload(file) }
    raise InvalidUpload.new(:unsupported_file) unless acceptable_uploads?(uploads)

    pdf_upload = uploads.first if uploads.first[:content_type] == PaperScan::PDF_TYPE
    pdf_upload[:metadata] = { "page_count" => read_page_count(pdf_upload[:io]) } if pdf_upload

    added = with_lock do
      next [] unless draft?

      if pdf_upload
        pages.destroy_all
      else
        pdf_pages, image_pages = pages.partition(&:pdf?)
        raise too_many_pages if image_pages.size + uploads.size > MAX_PAGES

        pdf_pages.each(&:destroy!)
      end

      position = pages.maximum(:position).to_i
      uploads.map do |upload|
        position += 1
        pages.create!(position: position, file: upload.merge(identify: false))
      end
    end

    pages.reset
    broadcast_refresh_to(self) if added.any?
    added
  end

  def remove_page!(page)
    removed = with_lock do
      next false unless draft?

      pages.find(page.id).destroy!
      renumber_pages!(pages.reload.to_a)
      true
    end

    broadcast_refresh_to(self) if removed
  end

  # Moves the page to +position+ (1 is the first page).
  def move_page!(page, position)
    moved = with_lock do
      next false unless draft?

      page = pages.find(page.id)
      ordered = pages.reload.to_a
      ordered.delete(page)
      ordered.insert((position.to_i - 1).clamp(0, ordered.size), page)
      renumber_pages!(ordered)
      true
    end

    broadcast_refresh_to(self) if moved
  end

  # Pages of the printed document; nil when they cannot be counted.
  def expected_page_count
    return @expected_page_count if defined?(@expected_page_count)

    document = contract.documents.first
    @expected_page_count = (stored_page_count(document.blob.blob) if document&.is_pdf?)
  end

  # Pages of the scan, of the uploaded PDF or the number of photos; nil when a PDF cannot be read.
  def uploaded_page_count
    return stored_page_count(scan.blob) if scan.attached?

    pdf_page = pages.find(&:pdf?)
    pdf_page ? stored_page_count(pdf_page.file.blob) : pages.size
  end

  # Builds the scan from the pages and hands it over for review. Returns true when submitted; false
  # for a draft without pages, a paper signature that is no longer a draft, or one whose pages changed
  # while the scan was being built (e.g. from the phone), so the signer sees the current state.
  def submit!
    snapshot = pages.reload.to_a
    return false unless draft? && snapshot.any?

    # A scan is about as large as its pages: pages over the limit are refused before they are read.
    max = PlanLimits.max_document_bytes
    raise InvalidUpload.new(:too_large) if max && snapshot.sum { |page| page.file.byte_size } > max

    # Built outside the row lock, which cancel! (withdrawal, superseding) must not wait for.
    content = build_scan(snapshot)
    raise InvalidUpload.new(:too_large) if max && content.bytesize > max

    pdf_page = snapshot.find(&:pdf?)
    page_count = pdf_page ? stored_page_count(pdf_page.file.blob) : snapshot.size

    submitted = with_lock do
      next false unless draft? && pages.ids == snapshot.map(&:id)

      self.scan = { io: StringIO.new(content), filename: scan_filename, content_type: PaperScan::PDF_TYPE, identify: false, metadata: { "page_count" => page_count } }
      update!(status: :submitted, submitted_at: Time.current)
      true
    end

    if submitted
      broadcast_state_change
      Notification::PaperSignatureSubmittedJob.perform_later(self)
    end
    submitted
  rescue ActiveStorage::FileNotFoundError
    false # a page was removed while the scan was being built
  end

  # The signer counts as signed from now on; the reviewer gets no mail about it. A signing app the
  # signer opened before submitting the scan can no longer sign for them.
  def approve!(reviewer)
    transaction do
      lock_for_review!
      update!(status: :approved, reviewed_by: reviewer, reviewed_at: Time.current)
      pages.destroy_all
      signer_contract.complete_signature!(at: reviewed_at, except: reviewer)
      signer_contract.sessions.pending.find_each(&:canceled!)
    end

    broadcast_state_change
    Notification::PaperSignatureReviewedJob.perform_later(self)
  end

  # Sends the scan back to the signer, who may upload a new one.
  def return!(reviewer, reason)
    transaction do
      lock_for_review!
      update!(status: :returned, reviewed_by: reviewer, reviewed_at: Time.current, return_reason: reason)
      pages.destroy_all
    end

    broadcast_state_change
    Notification::PaperSignatureReviewedJob.perform_later(self)
  end

  # The signer discarded the scan or their signature is no longer needed.
  def cancel!
    canceled = with_lock do
      next false unless open?

      update!(status: :canceled)
      pages.destroy_all
      true
    end

    broadcast_state_change if canceled
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  # The size comes from the upload's metadata and Marcel reads only the first bytes, so a refused
  # file is never read whole. A PNG is checked before Prawn inflates it on submit.
  def identify_upload(file)
    raise InvalidUpload.new(:file_too_large, size: MAX_FILE_BYTES / 1.megabyte) if file.size > MAX_FILE_BYTES

    content_type = Marcel::MimeType.for(file)
    file.rewind
    problem = PaperScan.png_problem(file) if content_type == "image/png"
    raise InvalidUpload.new(problem) if problem

    { io: file, filename: file.original_filename.presence || "page", content_type: content_type }
  end

  # Uploaded files cannot seek, which the PDF reader needs.
  def read_page_count(file)
    PaperScan.page_count(file.read)
  ensure
    file.rewind
  end

  # Counted once and kept in the blob's metadata, so pages render without parsing the PDF again.
  # Scans and uploaded PDFs are counted when they are stored, the printed document on first use.
  def stored_page_count(blob)
    return blob.metadata["page_count"] if blob.metadata.key?("page_count")

    PaperScan.page_count(blob.download).tap do |count|
      blob.update_columns(metadata: blob.metadata.merge("page_count" => count))
    end
  end

  def too_many_pages
    InvalidUpload.new(:too_many_pages, count: MAX_PAGES)
  end

  # Photos only, or a single PDF.
  def acceptable_uploads?(uploads)
    types = uploads.map { |upload| upload[:content_type] }
    return false if types.empty?

    types == [ PaperScan::PDF_TYPE ] || types.all? { |type| PaperScan::IMAGE_TYPES.include?(type) }
  end

  def renumber_pages!(ordered)
    ordered.each.with_index(1) do |page, position|
      page.update!(position: position) if page.position != position
    end
  end

  def build_scan(snapshot)
    pdf_page = snapshot.find(&:pdf?)
    return pdf_page.file.download if pdf_page

    images = snapshot.map { |page| [ page.file.download, page.file.content_type ] }
    begin
      PaperScan.combine(images)
    rescue StandardError => e
      # Prawn::Errors::UnsupportedImageType, or whatever a damaged image makes Prawn raise.
      Rails.error.report(e, context: { paper_signature_id: id })
      raise InvalidUpload.new(:unsupported_file)
    end
  end

  def scan_filename
    "#{File.basename(contract.documents.first&.filename.to_s, '.*').presence || 'document'}-scan.pdf"
  end

  def lock_for_review!
    lock!
    signer_contract.lock!
    raise NoLongerReviewable unless reviewable?
  end

  def broadcast_state_change
    broadcast_refresh_to(self)
    broadcast_refresh_to(contract)
  end
end
