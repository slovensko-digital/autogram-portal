require "test_helper"

class SignerContractTest < ActiveSupport::TestCase
  test "completing a signature marks it signed and counts the signature request" do
    tenant = Tenant.create!(name: "Firma ABC", plan: :pro)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 test"), filename: "zmluva.pdf", content_type: "application/pdf")
    contract = Contract.create!(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
    bundle = Bundle.create!(tenant: tenant, contracts: [ contract ])
    recipient = bundle.recipients.create!(email: "external@example.com", locale: "en")
    recipient.update!(notified_at: Time.current)
    signer_contract = recipient.signer_contracts.find_by!(contract: contract)

    signer_contract.complete_signature!(at: Time.zone.parse("2026-11-25 15:02"))

    assert_equal Time.zone.parse("2026-11-25 15:02"), signer_contract.reload.signed_at
    assert bundle.reload.completed?
    assert_equal 1, UsageRecord.signature_request.where(contract: contract).count
  end
end
