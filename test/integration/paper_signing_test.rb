require "test_helper"
require_relative "../support/signing_flow_helper"

# Signing on paper: the recipient uploads a scan of the document signed by hand and the
# sending organization reviews it.
class PaperSigningTest < ActionDispatch::IntegrationTest
  include SigningFlowHelper

  setup do
    @organization = Tenant.create!(name: "Firma ABC", plan: :pro)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(Prawn::Document.new { text "a"; start_new_page; text "b" }.render),
      filename: "zmluva.pdf",
      content_type: "application/pdf"
    )
    @contract = Contract.create!(documents_attributes: [ { blob: blob } ], signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" })
    @bundle = Bundle.create!(tenant: @organization, contracts: [ @contract ])
    @recipient = @bundle.recipients.create!(email: "external@example.com", locale: "sk")
  end

  test "a declined bundle cancels the recipient's open scan" do
    paper = PaperSignature.open_for!(@recipient.signer_contracts.sole)
    paper.add_pages!([ Rack::Test::UploadedFile.new(file_fixture("paper-page.jpg"), "image/jpeg") ])
    paper.submit!

    post decline_bundle_path(@bundle, recipient: @recipient.uuid)

    assert_redirected_to sign_bundle_path(@bundle, recipient: @recipient.uuid)
    assert @recipient.reload.declined?
    assert paper.reload.canceled?
  end
end
