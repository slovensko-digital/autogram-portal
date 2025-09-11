require "test_helper"

class AutogramServiceTest < ActiveSupport::TestCase
  test "validates file without signatures" do
    user = users(:one)
    document = Document.new(user: user, uuid: SecureRandom.uuid)

    # Mock a regular PDF file attachment
    pdf_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake pdf content"),
      filename: "document.pdf",
      content_type: "application/pdf"
    )
    document.blob.attach(pdf_blob)

    result = AutogramService.validate_signatures(document)

    assert result.valid_response?
    assert_not result.has_signatures
    assert_equal 0, result.signature_count
    assert_equal "PAdES", result.document_info[:signature_form]
    assert_equal 1, result.document_info[:unsigned_objects_count]
  end

  test "validates file with existing signature" do
    user = users(:one)
    document = Document.new(user: user, uuid: SecureRandom.uuid)

    # Mock a signed PDF file attachment (filename contains 'signed')
    pdf_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake signed pdf content"),
      filename: "document-signed.pdf",
      content_type: "application/pdf"
    )
    document.blob.attach(pdf_blob)

    result = AutogramService.validate_signatures(document)

    assert result.valid_response?
    assert result.has_signatures
    assert_equal 1, result.signature_count

    signature = result.signatures.first
    assert_equal "Ján Novák", signature[:signer_name]
    assert_equal "PAdES_BASELINE_B", signature[:signature_level]
    assert_equal "TOTAL_PASSED", signature[:validation_result]
    assert signature[:valid]
  end

  test "validates file with timestamped signature" do
    user = users(:one)
    document = Document.new(user: user, uuid: SecureRandom.uuid)

    # Mock a timestamped file attachment
    pdf_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake timestamped pdf content"),
      filename: "document-timestamp.pdf",
      content_type: "application/pdf"
    )
    document.blob.attach(pdf_blob)

    result = AutogramService.validate_signatures(document)

    assert result.valid_response?
    assert result.has_signatures
    assert_equal 1, result.signature_count

    signature = result.signatures.first
    assert_equal "Mária Svobodová", signature[:signer_name]
    assert_equal "PAdES_BASELINE_T", signature[:signature_level]
    assert_not_nil signature[:timestamp_info]
    assert signature[:timestamp_info][:qualified]
    assert_equal 1, signature[:timestamp_info][:count]
    assert_equal "TSA Authority SK", signature[:timestamp_info][:timestamps].first[:authority]
  end

  test "handles file without attachment" do
    user = users(:one)
    document = Document.new(user: user, uuid: SecureRandom.uuid)

    result = AutogramService.validate_signatures(document)

    assert_not result.valid_response?
    assert_includes result.errors.first, "Súbor nie je pripojený"
  end

  test "signing file model integration" do
    user = users(:one)
    document = Document.new(user: user, uuid: SecureRandom.uuid)

    # Mock a signed file
    pdf_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("fake signed content"),
      filename: "signed-document.pdf",
      content_type: "application/pdf"
    )
    document.blob.attach(pdf_blob)

    assert document.has_signatures?

    validation = document.validate_signatures
    assert validation.has_signatures
  end
end
