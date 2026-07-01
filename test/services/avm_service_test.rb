require "test_helper"

class AvmServiceTest < ActiveSupport::TestCase
  test "detached signing base url falls back to autogram service url" do
    service = AvmService.new

    with_env("AUTOGRAM_SERVICE_URL" => "http://127.0.0.1:7200", "AVM_DETACHED_URL" => nil, "AVM_URL" => nil) do
      assert_equal "http://127.0.0.1:7200", service.send(:detached_signing_base_url)
      assert_equal "https://autogram.slovensko.digital", service.send(:interactive_base_url)
    end
  end

  test "detached signing base url prefers dedicated env override" do
    service = AvmService.new

    with_env("AUTOGRAM_SERVICE_URL" => "http://127.0.0.1:7200", "AVM_DETACHED_URL" => "https://detached.example.test") do
      assert_equal "https://detached.example.test", service.send(:detached_signing_base_url)
    end
  end

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

  test "detached signing payload includes public signature reference" do
    contract = Contract.create!(
      documents_attributes: [ { blob: pdf_blob("sample.pdf", "%PDF-1.4 original") } ],
      signature_parameters_attributes: { level: "BASELINE_B", format: "XAdES" }
    )
    bundle = Bundle.create!(author: users(:one), contracts: [ contract ])
    recipient = bundle.recipients.create!(email: "recipient-#{SecureRandom.hex(4)}@example.com", locale: "en")
    signer_contract = recipient.signer_contracts.find_by!(contract: contract)
    service = AvmService.new
    captured = []

    service.define_singleton_method(:call_avm_data_to_sign_api) do |payload|
      captured << payload
      Struct.new(:success?, :body).new(true, {
        "dataToSign" => Base64.strict_encode64("payload"),
        "signingTime" => 1_783_000_000_000,
        "signingCertificate" => "cert"
      })
    end

    service.define_singleton_method(:call_avm_build_signature_api) do |payload|
      captured << payload
      Struct.new(:success?, :body).new(true, { "content" => Base64.strict_encode64("signed") })
    end

    data_to_sign = service.request_data_to_sign(
      contract,
      signer_contract: signer_contract,
      signing_certificate: "encoded-cert",
      signature_reference: "PUBLIC-REF-123",
      signature_instance: "agp.example.test"
    )
    service.build_signed_document(
      contract,
      signer_contract: signer_contract,
      data_to_sign_structure: data_to_sign,
      signed_data: "signed-data",
      signature_reference: "PUBLIC-REF-123",
      signature_instance: "agp.example.test"
    )

    assert_equal "PUBLIC-REF-123", captured.first.dig(:originalSignRequestBody, :parameters, :signatureReference)
    assert_equal "PUBLIC-REF-123", captured.last.dig(:originalSignRequestBody, :parameters, :signatureReference)
    assert_equal "agp.example.test", captured.first.dig(:originalSignRequestBody, :parameters, :signatureInstance)
    assert_equal "agp.example.test", captured.last.dig(:originalSignRequestBody, :parameters, :signatureInstance)
    assert_equal "DETACHED", captured.first.dig(:originalSignRequestBody, :parameters, :packaging)
    assert_equal "DETACHED", captured.last.dig(:originalSignRequestBody, :parameters, :packaging)
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

  def with_env(overrides)
    original_values = overrides.transform_values { |_,| nil }
    overrides.each_key { |key| original_values[key] = ENV[key] }
    overrides.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    yield
  ensure
    original_values.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
