require "application_system_test_case"
require_relative "../support/signing_flow_helper"

# The paper signing page uploads photos and scans as soon as they are picked (paper-pages Stimulus
# controller) and shows the page tiles when the Turbo refresh arrives. Runs with forgery protection
# on, as in production, so the upload must send the CSRF token of the page.
class PaperSigningSystemTest < ApplicationSystemTestCase
  include SigningFlowHelper
  include Devise::Test::IntegrationHelpers

  setup do
    @original_allowed_methods = Contract::ALLOWED_METHODS
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, %w[qes standalone_qes ades scan])

    Rails.application.config.action_controller.default_url_options = {}
    @original_allow_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    @organization = Tenant.create!(name: "Firma ABC", plan: :pro)
    @bundle = Bundle.create!(
      tenant: @organization,
      contracts_attributes: [ {
        allowed_methods: [ "qes", "scan" ],
        signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" },
        documents_attributes: [ { blob: two_page_pdf_blob } ]
      } ],
      recipients_attributes: [ { email: "paper@example.com" } ]
    )
    @contract = @bundle.contracts.sole
    @recipient = @bundle.recipients.sole
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @original_allow_forgery_protection
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, @original_allowed_methods)
  end

  test "recipient drops a photo, sees the page tile and submits" do
    visit contract_paper_signature_path(@contract, recipient: @recipient.uuid)

    # The upload starts by itself, so the button for browsers without JavaScript is hidden.
    assert_no_button I18n.t("paper_signatures.steps.upload.button")
    attach_file "files[]", file_fixture("paper-page.jpg"), make_visible: true

    assert_selector "figure", text: "Strana 1"
    click_on "Odoslať na kontrolu"

    assert_text "Sken sme odoslali na kontrolu"
    assert PaperSignature.sole.submitted?
  end

  test "a large photo is downsized before upload" do
    original = file_fixture("paper-page-large.jpg")
    visit contract_paper_signature_path(@contract, recipient: @recipient.uuid)

    attach_file "files[]", original, make_visible: true

    assert_selector "figure", text: "Strana 1"
    blob = PaperSignature.sole.pages.sole.file.blob
    assert_operator blob.byte_size, :<, original.size
    assert_equal "image/jpeg", blob.content_type
    assert_equal "paper-page-large.jpg", blob.filename.to_s

    width, height = jpeg_dimensions(blob.download)
    assert_equal 2400, [ width, height ].max
  end

  test "a small photo is redrawn upright, without its EXIF orientation" do
    # Stored as 800x600 landscape with Orientation=6, so it displays as 600x800 portrait.
    visit contract_paper_signature_path(@contract, recipient: @recipient.uuid)

    attach_file "files[]", file_fixture("paper-page-rotated.jpg"), make_visible: true

    assert_selector "figure", text: "Strana 1"
    bytes = PaperSignature.sole.pages.sole.file.download
    assert_equal [ 600, 800 ], jpeg_dimensions(bytes)
    assert_not_includes bytes.b, "Exif\x00\x00".b, "the upright copy carries no EXIF orientation"
  end

  test "a PDF scan is uploaded unchanged" do
    scan = Rails.root.join("tmp/paper-scan-#{SecureRandom.hex(4)}.pdf")
    scan.binwrite(two_page_pdf_content)
    visit contract_paper_signature_path(@contract, recipient: @recipient.uuid)

    attach_file "files[]", scan.to_s, make_visible: true

    assert_selector "figure", text: I18n.t("paper_signatures.pages.pdf")
    assert_equal scan.binread, PaperSignature.sole.pages.sole.file.download
  ensure
    scan&.delete
  end

  test "the server's refusal of a file is shown on the page" do
    visit contract_paper_signature_path(@contract, recipient: @recipient.uuid)

    attach_file "files[]", Rails.root.join("README.md").to_s, make_visible: true

    assert_selector "[role=alert]", text: I18n.t("paper_signatures.errors.unsupported_file")
    assert_no_selector "figure"
  end

  test "pages taken on the phone appear on the computer and the phone shows the confirmation after the computer submits" do
    visit contract_paper_signature_path(@contract, recipient: @recipient.uuid)
    phone_url = find("#paper_signature_phone [data-phone-url]", visible: :all)["data-phone-url"]

    Capybara.using_session(:phone) do
      visit phone_url
      assert_text I18n.t("paper_signatures.phone_page.title")
      attach_file "files[]", file_fixture("paper-page.png"), match: :first, make_visible: true
      assert_selector "figure", text: "Strana 1"
    end

    assert_selector "figure", text: "Strana 1"
    click_on "Odoslať na kontrolu"
    assert_text "Sken sme odoslali na kontrolu"

    Capybara.using_session(:phone) do
      # The refresh renders the 410 page of the phone link, which confirms the submitted scan.
      assert_text "Sken sme odoslali na kontrolu"
      assert_no_selector "figure"
    end
  ensure
    Capybara.using_session(:phone) { Capybara.current_session.quit }
  end

  test "a member returns a scan with a reason in the dialog and approves the next one" do
    owner = confirmed_user("owner@firma-abc.sk", tenant: @organization, role: :owner)
    returned = submitted_paper_signature
    sign_in owner

    visit bundle_paper_signature_path(@bundle, returned)
    click_on "Firma ABC"
    assert_selector "h1", text: "Kontrola podpisu na papieri"
    assert_selector "iframe", count: 2
    assert_no_selector "dialog[open]"

    click_on "Vrátiť sken"
    within "dialog[open]" do
      assert_text "paper@example.com dostane e-mail s vaším dôvodom"
      click_on "Zrušiť"
    end
    assert_no_selector "dialog[open]"

    click_on "Vrátiť sken"
    within "dialog[open]" do
      fill_in "Dôvod", with: "Chýba podpis na strane 2."
      click_on "Vrátiť sken"
    end
    assert_text "Sken sme vrátili."
    assert returned.reload.returned?
    assert_equal "Chýba podpis na strane 2.", returned.return_reason

    approved = submitted_paper_signature
    visit bundle_paper_signature_path(@bundle, approved)
    click_on "Schváliť podpis"
    assert_text "Podpis na papieri sme schválili."
    assert approved.reload.approved?
    assert @bundle.reload.completed?
  end

  private

  def submitted_paper_signature
    paper = PaperSignature.open_for!(@recipient.recipient_signer.signer_contracts.sole)
    paper.add_pages!([ Rack::Test::UploadedFile.new(file_fixture("paper-page.jpg"), "image/jpeg") ])
    assert paper.submit!
    paper
  end

  def two_page_pdf_content
    Prawn::Document.new { |pdf| pdf.text "Strana 1"; pdf.start_new_page; pdf.text "Strana 2" }.render
  end

  def two_page_pdf_blob
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(two_page_pdf_content), filename: "papier.pdf", content_type: "application/pdf")
  end

  # Reads the size from the start-of-frame marker.
  def jpeg_dimensions(bytes)
    offset = 2
    while offset < bytes.bytesize
      marker = bytes.getbyte(offset + 1)
      length = bytes.byteslice(offset + 2, 2).unpack1("n")
      return bytes.byteslice(offset + 5, 4).unpack("nn").reverse if [ 0xC0, 0xC1, 0xC2 ].include?(marker)

      offset += 2 + length
    end
  end
end
