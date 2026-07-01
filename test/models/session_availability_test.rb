require "test_helper"

class SessionAvailabilityTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  test "eidentita and podpisuj are unavailable when prepared signature fields are attached" do
    contract = contract_with_prepared_signature_fields

    assert AutogramSession.available?(nil, contract)
    assert AvmSession.available?(nil, contract)
    assert_not EidentitaSession.available?(nil, contract)
    assert_not PodpisujSession.available?(nil, contract)
  end

  test "eidentita and podpisuj remain available without prepared signature fields" do
    contract = Contract.create!(
      documents_attributes: [ { blob: pdf_blob("plain.pdf", "%PDF-1.4 original") } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
    Bundle.create!(author: @user, contracts: [ contract ])

    assert EidentitaSession.available?(nil, contract)
    assert PodpisujSession.available?(nil, contract)
  end

  private

  def contract_with_prepared_signature_fields
    contract = Contract.create!(
      documents_attributes: [ { blob: pdf_blob("prepared.pdf", "%PDF-1.4 original") } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
    Bundle.create!(author: @user, contracts: [ contract ])

    contract.add_prepared_signature_fields_content_version!(
      content: "%PDF-1.4 prepared source",
      filename: "prepared-fields.pdf",
      content_type: "application/pdf"
    )

    contract.reload
  end

  def pdf_blob(filename, content)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(content),
      filename: filename,
      content_type: "application/pdf"
    )
  end
end
