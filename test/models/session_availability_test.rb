require "test_helper"

class SessionAvailabilityTest < ActiveSupport::TestCase
  def setup
    @user = users(:one)
  end

  test "eidentita and podpisuj are unavailable when prepared signature fields are attached" do
    contract = contract_with_prepared_signature_fields

    assert_not AutogramSession.available?(nil, contract)
    assert AvmSession.available?(nil, contract)
    assert_not EidentitaSession.available?(nil, contract)
    assert_not PodpisujSession.available?(nil, contract)
    assert_equal [ :prepared_signature_fields ], AutogramSession.unavailability_reasons(nil, contract)
    assert_empty AvmSession.unavailability_reasons(nil, contract)
    assert_equal [ :prepared_signature_fields ], EidentitaSession.unavailability_reasons(nil, contract)
    assert_equal [ :prepared_signature_fields ], PodpisujSession.unavailability_reasons(nil, contract)
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

  test "mobile apps report unsupported qscd" do
    contract = plain_contract

    assert_equal [ :unsupported_qscd ], AvmSession.unavailability_reasons("eid_2021", contract)
    assert_equal [ :unsupported_qscd ], EidentitaSession.unavailability_reasons("eid_2021", contract)
    assert_not AvmSession.available?("eid_2021", contract)
    assert_not EidentitaSession.available?("eid_2021", contract)
    assert_empty AvmSession.unavailability_reasons("eid_2024", contract)
    assert_empty EidentitaSession.unavailability_reasons("eid_2024", contract)
  end

  test "document constraints return all applicable reasons" do
    contract = multiple_file_contract

    assert_empty AutogramSession.unavailability_reasons("eid_2021", contract)
    assert_equal [ :multiple_files, :unsupported_qscd ], AvmSession.unavailability_reasons("eid_2021", contract)
    assert_equal [ :multiple_files, :unsupported_qscd ], EidentitaSession.unavailability_reasons("eid_2021", contract)
    assert_equal [ :multiple_files ], PodpisujSession.unavailability_reasons("eid_2021", contract)
  end

  test "podpisuj reports unsupported signature level" do
    contract = plain_contract
    contract.signature_parameters.update!(level: "BASELINE_T")

    assert_equal [ :unsupported_signature_level ], PodpisujSession.unavailability_reasons(nil, contract)
    assert_not PodpisujSession.available?(nil, contract)
  end

  test "ades evidence session is available for recipient mobile phone or email" do
    contract = Contract.create!(
      documents_attributes: [ { blob: pdf_blob("ades.pdf", "%PDF-1.4 original") } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" },
      allowed_methods: [ "ades" ]
    )
    bundle = Bundle.create!(author: @user, contracts: [ contract ])
    recipient = bundle.recipients.create!(email: "ades@example.com", locale: "en")

    assert AdesEvidenceSession.available?(contract, recipient: recipient)

    recipient.update!(mobile_phone: "+421901234567")

    assert AdesEvidenceSession.available?(contract, recipient: recipient)
    assert_not AdesEvidenceSession.available?(contract, recipient: nil)
  end

  private

  def plain_contract
    Contract.create!(
      documents_attributes: [ { blob: pdf_blob("plain.pdf", "%PDF-1.4 original") } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
  end

  def multiple_file_contract
    Contract.create!(
      documents_attributes: [
        { blob: pdf_blob("first.pdf", "%PDF-1.4 first") },
        { blob: pdf_blob("second.pdf", "%PDF-1.4 second") }
      ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "XAdES" }
    )
  end

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
