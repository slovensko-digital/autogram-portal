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
require "test_helper"
require_relative "../support/signing_flow_helper"
require_relative "../support/plan_limits_helper"

class PaperSignatureTest < ActiveSupport::TestCase
  include SigningFlowHelper
  include PlanLimitsHelper
  include ActiveJob::TestHelper

  setup do
    @tenant = Tenant.create!(name: "Firma ABC", plan: :pro)
    @reviewer = confirmed_user("owner@firma-abc.sk", tenant: @tenant, role: :owner)
    @bundle = Bundle.create!(tenant: @tenant, contracts: [ create_contract ])
    @recipient = @bundle.recipients.create!(email: "external@example.com", locale: "sk")
  end

  test "a signer contract has one open paper signature" do
    assert_equal PaperSignature.open_for!(signer_contract), PaperSignature.open_for!(signer_contract)
    assert_raises(ActiveRecord::RecordNotUnique) { signer_contract.paper_signatures.create!(status: :submitted) }
  end

  test "a paper signature is addressed by its uuid" do
    paper = PaperSignature.open_for!(signer_contract)

    assert paper.draft?
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, paper.to_param)
    assert_equal paper.uuid, paper.to_param
  end

  test "submitting photos stores one combined scan and approval signs the recipient" do
    paper = PaperSignature.open_for!(signer_contract)
    paper.add_pages!([ jpeg_upload, jpeg_upload ])
    paper.submit!
    assert paper.submitted?
    assert_equal 2, PaperScan.page_count(paper.scan.download)
    paper.approve!(reviewer)
    assert recipient.reload.signed?
    assert_equal reviewer, paper.reload.reviewed_by
  end

  test "approval completes the signature at the review time and keeps only the scan" do
    paper = submitted_paper_signature
    assert_in_delta Time.current, paper.submitted_at, 5.seconds

    paper.approve!(reviewer)

    paper.reload
    assert paper.approved?
    assert_equal paper.reviewed_at, signer_contract.reload.signed_at
    assert @bundle.reload.completed?
    assert_empty paper.pages
    assert paper.scan.attached?
  end

  test "a returned scan keeps its reason and leaves the recipient pending" do
    paper = submitted_paper_signature
    paper.return!(reviewer, "Na strane 2 chýba podpis.")
    assert paper.returned?
    assert recipient.reload.pending?
  end

  test "a returned scan is history and the next upload starts a new draft" do
    paper = submitted_paper_signature
    paper.return!(reviewer, "Na strane 2 chýba podpis.")

    paper.reload
    assert_equal "Na strane 2 chýba podpis.", paper.return_reason
    assert_equal reviewer, paper.reviewed_by
    assert_empty paper.pages
    assert paper.scan.attached?
    assert_not_equal paper, PaperSignature.open_for!(signer_contract)
    assert_equal 2, signer_contract.paper_signatures.count
  end

  test "returning needs a reason" do
    assert_raises(ActiveRecord::RecordInvalid) { submitted_paper_signature.return!(reviewer, "") }
  end

  test "only a submitted scan of an awaiting signer contract can be reviewed" do
    draft = PaperSignature.open_for!(signer_contract)

    assert_raises(PaperSignature::NoLongerReviewable) { draft.approve!(reviewer) }
    assert_raises(PaperSignature::NoLongerReviewable) { draft.return!(reviewer, "Chýba podpis.") }
    assert draft.reload.draft?
  end

  test "a scan over the document size limit is not submitted" do
    with_plan_limits("MAX_DOCUMENT_SIZE_MB" => "0") do
      paper = PaperSignature.open_for!(signer_contract)
      paper.add_pages!([ jpeg_upload ])
      error = assert_raises(PaperSignature::InvalidUpload) { paper.submit! }
      assert_equal I18n.t("paper_signatures.errors.too_large"), error.message
      assert paper.reload.draft?
      assert_not paper.scan.attached?
    end
  end

  test "an uploaded PDF replaces photos and is the scan as it is" do
    paper = PaperSignature.open_for!(signer_contract)
    paper.add_pages!([ jpeg_upload ])
    paper.add_pages!([ pdf_upload(pages: 2) ])
    assert_equal 1, paper.pages.count
    assert_equal 2, paper.uploaded_page_count

    paper.submit!

    assert_equal paper.pages.sole.file.download, paper.scan.download
  end

  test "photos replace an uploaded PDF" do
    paper = PaperSignature.open_for!(signer_contract)
    paper.add_pages!([ pdf_upload(pages: 2) ])
    paper.add_pages!([ jpeg_upload ])

    assert paper.pages.sole.image?
    assert_equal 1, paper.uploaded_page_count
  end

  test "pages are counted against the pages of the document" do
    paper = PaperSignature.open_for!(signer_contract)
    pages = paper.add_pages!([ jpeg_upload, png_upload ])

    assert_equal 2, paper.expected_page_count
    assert_equal 2, paper.uploaded_page_count
    assert_equal [ 1, 2 ], pages.map(&:position)
    assert pages.all?(&:image?)
    assert_not pages.first.pdf?
  end

  test "the file type comes from the content, not from what the browser declares" do
    paper = PaperSignature.open_for!(signer_contract)
    page = paper.add_pages!([ Rack::Test::UploadedFile.new(file_fixture("paper-page.png"), "application/pdf") ]).sole

    assert page.image?
    assert_equal "image/png", page.file.content_type

    error = assert_raises(PaperSignature::InvalidUpload) do
      paper.add_pages!([ Rack::Test::UploadedFile.new(StringIO.new("PK\x03\x04 zmluva.docx"), "image/jpeg", original_filename: "zmluva.jpg") ])
    end
    assert_equal I18n.t("paper_signatures.errors.unsupported_file"), error.message
    assert_equal 1, paper.pages.count
  end

  test "a PDF is accepted only on its own" do
    paper = PaperSignature.open_for!(signer_contract)

    assert_raises(PaperSignature::InvalidUpload) { paper.add_pages!([ pdf_upload(pages: 1), jpeg_upload ]) }
    assert_raises(PaperSignature::InvalidUpload) { paper.add_pages!([ pdf_upload(pages: 1), pdf_upload(pages: 1) ]) }
    assert_raises(PaperSignature::InvalidUpload) { paper.add_pages!([]) }
    assert_empty paper.pages
  end

  test "a draft takes a limited number of pages" do
    paper = PaperSignature.open_for!(signer_contract)
    too_many = I18n.t("paper_signatures.errors.too_many_pages", count: PaperSignature::MAX_PAGES)

    error = assert_raises(PaperSignature::InvalidUpload) { paper.add_pages!(Array.new(PaperSignature::MAX_PAGES + 1) { jpeg_upload }) }
    assert_equal too_many, error.message
    assert_empty paper.pages

    paper.add_pages!(Array.new(PaperSignature::MAX_PAGES) { jpeg_upload })
    error = assert_raises(PaperSignature::InvalidUpload) { paper.add_pages!([ jpeg_upload ]) }
    assert_equal too_many, error.message
    assert_equal PaperSignature::MAX_PAGES, paper.pages.count

    paper.add_pages!([ pdf_upload(pages: 2) ])
    assert_equal 1, paper.pages.count
  end

  test "a file over the size limit is refused before it is read" do
    paper = PaperSignature.open_for!(signer_contract)
    huge = jpeg_upload
    huge.define_singleton_method(:size) { PaperSignature::MAX_FILE_BYTES + 1 }
    huge.define_singleton_method(:read) { |*| raise "the file was read before its size was checked" }

    error = assert_raises(PaperSignature::InvalidUpload) { paper.add_pages!([ jpeg_upload, huge ]) }

    assert_equal I18n.t("paper_signatures.errors.file_too_large", size: 25), error.message
    assert_includes error.message, "25 MB"
    assert_empty paper.pages
  end

  test "a scan is not submitted when its pages changed while it was being built" do
    paper = PaperSignature.open_for!(signer_contract)
    paper.add_pages!([ jpeg_upload ])
    phone = PaperSignature.find(paper.id)
    phone_upload = png_upload
    paper.define_singleton_method(:build_scan) do |snapshot|
      phone.add_pages!([ phone_upload ])
      super(snapshot)
    end

    assert_not paper.submit!

    assert paper.reload.draft?
    assert_not paper.scan.attached?
    assert_equal 2, paper.pages.count
    assert PaperSignature.find(paper.id).submit!
  end

  test "an image the scan cannot be built from is refused on submit" do
    paper = PaperSignature.open_for!(signer_contract)
    paper.add_pages!([ Rack::Test::UploadedFile.new(StringIO.new("\x89PNG\r\n\x1A\n".b + "damaged".b), "image/png", original_filename: "strana.png") ])

    error = assert_raises(PaperSignature::InvalidUpload) { paper.submit! }
    assert_equal I18n.t("paper_signatures.errors.unsupported_file"), error.message
    assert paper.reload.draft?
  end

  test "pages can be removed and reordered while collecting them" do
    paper = PaperSignature.open_for!(signer_contract)
    first, second, third = paper.add_pages!([ jpeg_upload, png_upload, jpeg_upload ])

    paper.move_page!(third, 1)
    assert_equal [ third, first, second ], paper.pages.reload.to_a
    assert_equal [ 1, 2, 3 ], paper.pages.map(&:position)

    paper.remove_page!(first)
    assert_equal [ third, second ], paper.pages.reload.to_a
    assert_equal [ 1, 2 ], paper.pages.map(&:position)

    paper.add_pages!([ jpeg_upload ])
    assert_equal [ 1, 2, 3 ], paper.pages.reload.map(&:position)
  end

  test "a submitted scan takes no more pages and a draft without pages is not submitted" do
    empty = PaperSignature.open_for!(signer_contract)
    assert_not empty.submit!
    assert empty.reload.draft?

    paper = submitted_paper_signature
    assert_empty paper.add_pages!([ jpeg_upload ])
    assert_equal 1, paper.pages.count
  end

  test "withdrawing the recipient cancels the open paper signature and it can no longer be approved" do
    paper = submitted_paper_signature
    recipient.withdraw!
    assert paper.reload.canceled?
    assert_raises(PaperSignature::NoLongerReviewable) { paper.approve!(reviewer) }
  end

  test "a superseded signer contract's scan is canceled" do
    @bundle.update!(signing_rule: "any")
    other = @bundle.recipients.create!(email: "other@example.com", locale: "sk")
    paper = submitted_paper_signature

    other.signer_contracts.sole.complete_signature!

    assert signer_contract.reload.superseded?
    assert paper.reload.canceled?
    assert_empty paper.pages
    assert_raises(PaperSignature::NoLongerReviewable) { paper.return!(reviewer, "Chýba podpis.") }
  end

  test "canceling leaves a reviewed scan as it is" do
    paper = submitted_paper_signature
    paper.approve!(reviewer)

    paper.cancel!

    assert paper.reload.approved?
  end

  test "a draft is canceled with its pages" do
    paper = PaperSignature.open_for!(signer_contract)
    paper.add_pages!([ jpeg_upload ])

    paper.cancel!

    assert paper.reload.canceled?
    assert_empty paper.pages
    assert_equal 0, PaperSignaturePage.count
  end

  test "an approved scan stays approved when its reviewer deletes their account" do
    colleague = confirmed_user("colleague@firma-abc.sk", tenant: @tenant)
    paper = submitted_paper_signature
    paper.approve!(colleague)

    colleague.destroy!

    assert paper.reload.approved?
    assert_nil paper.reviewed_by
    assert_not_nil paper.reviewed_at
  end

  test "deleting the bundle deletes its paper signatures" do
    submitted_paper_signature

    @bundle.destroy!

    assert_equal 0, PaperSignature.count
    assert_equal 0, PaperSignaturePage.count
  end

  test "submitting, approving and returning enqueue the notification jobs only when they happen" do
    ActiveJob::Base.queue_adapter = :test
    paper = PaperSignature.open_for!(signer_contract)
    paper.add_pages!([ jpeg_upload ])

    assert_enqueued_with(job: Notification::PaperSignatureSubmittedJob, args: [ paper ]) { assert paper.submit! }
    assert_no_enqueued_jobs(only: Notification::PaperSignatureSubmittedJob) { assert_not paper.submit! }
    assert_enqueued_with(job: Notification::PaperSignatureReviewedJob, args: [ paper ]) { paper.approve!(reviewer) }
    assert_no_enqueued_jobs(only: Notification::PaperSignatureReviewedJob) do
      assert_raises(PaperSignature::NoLongerReviewable) { paper.approve!(reviewer) }
    end

    other = Bundle.create!(tenant: @tenant, contracts: [ create_contract ])
    other_contract = other.recipients.create!(email: "other@example.com", locale: "sk").signer_contracts.sole
    returned = PaperSignature.open_for!(other_contract)
    returned.add_pages!([ jpeg_upload ])
    returned.submit!
    assert_enqueued_with(job: Notification::PaperSignatureReviewedJob, args: [ returned ]) { returned.return!(reviewer, "Chýba podpis.") }
    assert_no_enqueued_jobs(only: Notification::PaperSignatureReviewedJob) do
      assert_raises(ActiveRecord::RecordInvalid) { PaperSignature.open_for!(other_contract).tap { |p| p.update!(status: :submitted) }.return!(reviewer, "") }
    end
  ensure
    ActiveJob::Base.queue_adapter = GoodJob::Adapter.new(execution_mode: :inline)
  end

  private

  attr_reader :reviewer, :recipient

  def signer_contract
    recipient.signer_contracts.sole
  end

  def submitted_paper_signature
    paper = PaperSignature.open_for!(signer_contract)
    paper.add_pages!([ jpeg_upload ])
    assert paper.submit!
    paper
  end

  def create_contract
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(pdf_content(pages: 2)), filename: "zmluva.pdf", content_type: "application/pdf")
    Contract.create!(documents_attributes: [ { blob: blob } ], signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" })
  end

  def pdf_content(pages:)
    Prawn::Document.new do |pdf|
      pages.times do |index|
        pdf.start_new_page if index.positive?
        pdf.text "Strana #{index + 1}"
      end
    end.render
  end

  def jpeg_upload
    Rack::Test::UploadedFile.new(file_fixture("paper-page.jpg"), "image/jpeg")
  end

  def png_upload
    Rack::Test::UploadedFile.new(file_fixture("paper-page.png"), "image/png")
  end

  def pdf_upload(pages:)
    Rack::Test::UploadedFile.new(StringIO.new(pdf_content(pages: pages)), "application/pdf", original_filename: "sken.pdf")
  end
end
