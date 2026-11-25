require "test_helper"

class SignerContractTest < ActiveSupport::TestCase
  test "completing a signature marks it signed and counts the signature request" do
    signer_contract = recipient_signer_contract

    signer_contract.complete_signature!(at: Time.zone.parse("2026-11-25 15:02"))

    assert_equal Time.zone.parse("2026-11-25 15:02"), signer_contract.reload.signed_at
    assert signer_contract.contract.bundle.reload.completed?
    assert_equal 1, UsageRecord.signature_request.where(contract: signer_contract.contract).count
  end

  test "a signature made another way withdraws the scan awaiting review" do
    signer_contract = recipient_signer_contract
    paper = PaperSignature.open_for!(signer_contract)
    paper.add_pages!([ jpeg_upload ])
    assert paper.submit!
    assert signer_contract.paper_scan_awaiting_review?

    signer_contract.complete_signature!

    assert paper.reload.canceled?
    assert_not signer_contract.paper_scan_awaiting_review?
    assert signer_contract.reload.signed?
  end

  test "a signature made another way discards the draft of a paper signature" do
    signer_contract = recipient_signer_contract
    paper = PaperSignature.open_for!(signer_contract)
    paper.add_pages!([ jpeg_upload ])
    assert_not signer_contract.paper_scan_awaiting_review?, "a draft does not await review"

    signer_contract.complete_signature!

    assert paper.reload.canceled?
    assert_empty paper.pages
  end

  private

  def recipient_signer_contract
    tenant = Tenant.create!(name: "Firma ABC", plan: :pro)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 test"), filename: "zmluva.pdf", content_type: "application/pdf")
    contract = Contract.create!(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
    bundle = Bundle.create!(tenant: tenant, contracts: [ contract ])
    recipient = bundle.recipients.create!(email: "external@example.com", locale: "en")
    recipient.update!(notified_at: Time.current)
    recipient.signer_contracts.find_by!(contract: contract)
  end

  def jpeg_upload
    Rack::Test::UploadedFile.new(file_fixture("paper-page.jpg"), "image/jpeg")
  end
end
