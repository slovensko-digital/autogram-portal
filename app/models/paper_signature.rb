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

    def initialize(reason)
      @reason = reason
      super(I18n.t(reason, scope: "paper_signatures.errors"))
    end
  end

  # The scan is not awaiting review any more, or its signature is no longer needed (signed another
  # way, superseded, declined or withdrawn).
  class NoLongerReviewable < StandardError; end

  OPEN_STATUSES = %w[draft submitted].freeze

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

  # Adds photos (JPEG, PNG) after the current pages, or one PDF, which replaces all pages; photos
  # replace an uploaded PDF in turn. The type is read from the content, not from what the browser
  # declares. Returns the new pages; none when the paper signature is no longer a draft (e.g. the
  # phone uploads after the computer submitted).
  def add_pages!(files)
    uploads = Array(files).select { |file| file.respond_to?(:read) }.map { |file| read_upload(file) }
    raise InvalidUpload.new(:unsupported_file) unless acceptable_uploads?(uploads)

    added = with_lock do
      next [] unless draft?

      if uploads.first[:content_type] == PaperScan::PDF_TYPE
        pages.destroy_all
      else
        pages.select(&:pdf?).each(&:destroy!)
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

  # Pages of the document to sign; nil when they cannot be counted.
  def expected_page_count
    return @expected_page_count if defined?(@expected_page_count)

    document = contract.documents_to_sign.first
    @expected_page_count = (PaperScan.page_count(document.content) if document&.is_pdf?)
  end

  # Pages of the scan, of the uploaded PDF or the number of photos; nil when a PDF cannot be read.
  def uploaded_page_count
    return PaperScan.page_count(scan.download) if scan.attached?

    pdf_page = pages.find(&:pdf?)
    pdf_page ? PaperScan.page_count(pdf_page.file.download) : pages.size
  end

  # Builds the scan from the pages and hands it over for review. Does nothing for a draft without
  # pages or a paper signature that is no longer a draft.
  def submit!
    submitted = with_lock do
      next false unless draft? && pages.exists?

      content = build_scan
      max = PlanLimits.max_document_bytes
      raise InvalidUpload.new(:too_large) if max && content.bytesize > max

      self.scan = { io: StringIO.new(content), filename: scan_filename, content_type: PaperScan::PDF_TYPE, identify: false }
      update!(status: :submitted, submitted_at: Time.current)
      true
    end

    broadcast_state_change if submitted
  end

  # The signer counts as signed from now on; the reviewer gets no mail about it.
  def approve!(reviewer)
    transaction do
      lock_for_review!
      update!(status: :approved, reviewed_by: reviewer, reviewed_at: Time.current)
      pages.destroy_all
      signer_contract.complete_signature!(at: reviewed_at, except: reviewer)
    end

    broadcast_state_change
  end

  # Sends the scan back to the signer, who may upload a new one.
  def return!(reviewer, reason)
    transaction do
      lock_for_review!
      update!(status: :returned, reviewed_by: reviewer, reviewed_at: Time.current, return_reason: reason)
      pages.destroy_all
    end

    broadcast_state_change
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

  def read_upload(file)
    content = file.read
    file.rewind
    {
      io: StringIO.new(content),
      filename: file.original_filename.presence || "page",
      content_type: Marcel::MimeType.for(StringIO.new(content))
    }
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

  def build_scan
    pdf_page = pages.find(&:pdf?)
    return pdf_page.file.download if pdf_page

    images = pages.map { |page| [ page.file.download, page.file.content_type ] }
    begin
      PaperScan.combine(images)
    rescue StandardError
      # Prawn::Errors::UnsupportedImageType, or whatever a damaged image makes Prawn raise.
      raise InvalidUpload.new(:unsupported_file)
    end
  end

  def scan_filename
    "#{File.basename(contract.documents.first&.filename.to_s, '.*').presence || 'document'}-scan.pdf"
  end

  def lock_for_review!
    lock!
    signer_contract.lock!
    raise NoLongerReviewable unless submitted? && signer_contract.awaiting?
  end

  def broadcast_state_change
    broadcast_refresh_to(self)
    broadcast_refresh_to(contract)
  end
end
