require "test_helper"

class AvmServiceTest < ActiveSupport::TestCase
  test "initiate_signing includes visible signature text payload for text prepared signature fields" do
    contract, recipient = create_bundle_contract_with_prepared_signature_field
    signer_contract = recipient.signer_contracts.find_by!(contract: contract)
    signer_contract.visual_stamps.create!(
      document: contract.documents.first,
      purpose: :signature_field_appearance,
      page: 2,
      x: 42,
      y: 64,
      width: 180,
      height: 64,
      text: "Prepared signer name"
    )

    payload = capture_initiate_payload(contract, signer_contract)

    visible_signature = payload.dig(:parameters, :visibleSignature)
    assert_not_nil visible_signature
    assert_equal contract.signature_field_preparations.first.field_identifier, visible_signature[:fieldId]
    assert_equal VisualStamp.pades_visible_signature_text("Prepared signer name"), visible_signature[:text]
    assert_nil visible_signature[:image]
  end

  test "initiate_signing omits visible signature text for graphic prepared signature fields" do
    contract, recipient = create_bundle_contract_with_prepared_signature_field
    signer_contract = recipient.signer_contracts.find_by!(contract: contract)
    visual_stamp = signer_contract.visual_stamps.new(
      document: contract.documents.first,
      purpose: :signature_field_appearance,
      page: 2,
      x: 42,
      y: 64,
      width: 180,
      height: 64,
      text: nil
    )
    visual_stamp.image.attach(
      io: StringIO.new("fake-png-content"),
      filename: "signature.png",
      content_type: "image/png"
    )
    visual_stamp.save!

    payload = capture_initiate_payload(contract, signer_contract)

    visible_signature = payload.dig(:parameters, :visibleSignature)
    assert_not_nil visible_signature
    assert_equal contract.signature_field_preparations.first.field_identifier, visible_signature[:fieldId]
    refute visible_signature.key?(:text)
    assert_equal "signature.png", visible_signature.dig(:image, :filename)
    assert_equal "image/png;base64", visible_signature.dig(:image, :mimeType)
    assert_equal Base64.strict_encode64("fake-png-content"), visible_signature.dig(:image, :content)
  end

  test "initiate_signing omits visible signature when no signature field appearance exists" do
    contract, recipient = create_bundle_contract_with_prepared_signature_field
    signer_contract = recipient.signer_contracts.find_by!(contract: contract)

    payload = capture_initiate_payload(contract, signer_contract)

    assert_nil payload[:parameters][:visibleSignature]
  end

  private

  def capture_initiate_payload(contract, signer_contract)
    service = AvmService.new
    captured = nil
    service.define_singleton_method(:call_avm_initiate_api) do |payload, _secret_key|
      captured = payload
      Struct.new(:success?, :body, :headers).new(true, { "guid" => "guid-1" }, { "Last-Modified" => Time.current.httpdate })
    end

    service.initiate_signing(contract, signer_contract: signer_contract)
    captured
  end

  def create_bundle_contract_with_prepared_signature_field
    contract = Contract.create!(
      documents_attributes: [ { blob: pdf_blob("prepared.pdf", "%PDF-1.4 original") } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" }
    )
    bundle = Bundle.create!(author: users(:one), contracts: [ contract ])
    recipient = bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en")

    contract.signature_field_preparations.create!(
      recipient: recipient,
      document: contract.documents.first,
      page: 2,
      x: 42,
      y: 64,
      width: 180,
      height: 64
    )

    contract.add_prepared_signature_fields_content_version!(
      content: "%PDF-1.4 prepared source",
      filename: "prepared-fields.pdf",
      content_type: "application/pdf"
    )

    [ contract.reload, recipient.reload ]
  end

  def pdf_blob(filename, content)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(content),
      filename: filename,
      content_type: "application/pdf"
    )
  end
end
