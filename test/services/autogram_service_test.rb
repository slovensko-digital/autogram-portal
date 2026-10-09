require "test_helper"

class AutogramServiceTest < ActiveSupport::TestCase
  test "parse_validation_response maps signed object ids to per-signature objects" do
    response = {
      "containerType" => "ASiC_E",
      "signatureForm" => "XAdES",
      "signedObjects" => [
        { "id" => "id-xdcf", "filename" => "document.xdcf", "mimeType" => "application/octet-stream" },
        { "id" => "id-pdf", "filename" => "PdfDocument.pdf", "mimeType" => "application/pdf" },
        { "id" => "id-txt", "filename" => "TextDocument.txt", "mimeType" => "text/plain" }
      ],
      "signatures" => [
        {
          "validationResult" => "TOTAL_PASSED",
          "level" => "XAdES_BASELINE_B",
          "claimedSigningTime" => "2026-06-02T12:25:52 +0000",
          "signingCertificate" => {
            "qualification" => "NA",
            "issuerDN" => "CN=Issuer",
            "subjectDN" => "CN=Autogram Test"
          },
          "areQualifiedTimestamps" => false,
          "signedObjectsIds" => [ "id-xdcf", "id-pdf", "id-txt" ]
        },
        {
          "validationResult" => "TOTAL_PASSED",
          "level" => "XAdES_BASELINE_B",
          "claimedSigningTime" => "2026-06-02T14:11:55 +0000",
          "signingCertificate" => {
            "qualification" => "NA",
            "issuerDN" => "CN=Issuer",
            "subjectDN" => "CN=Autogram Test"
          },
          "areQualifiedTimestamps" => false,
          "signedObjectsIds" => [ "id-pdf" ]
        }
      ]
    }

    validation_result = AutogramService.new.send(:parse_validation_response, response)

    assert_equal [ "document.xdcf", "PdfDocument.pdf", "TextDocument.txt" ], validation_result.signatures.first.signedObjects.map { |object| object["filename"] }
    assert_equal [ "PdfDocument.pdf" ], validation_result.signatures.second.signedObjects.map { |object| object["filename"] }
  end

  test "parse_validation_response preserves signing certificate and timestamp expiry" do
    response = {
      "signatures" => [
        {
          "validationResult" => "TOTAL_PASSED",
          "level" => "PAdES_BASELINE_LTA",
          "claimedSigningTime" => "2026-06-02T12:25:52 +0000",
          "signingCertificate" => {
            "qualification" => "QESIG",
            "issuerDN" => "CN=Issuer",
            "subjectDN" => "CN=Autogram Test",
            "notAfter" => "2028-06-02T12:25:52 +0000"
          },
          "areQualifiedTimestamps" => true,
          "timestamps" => [
            {
              "timestampType" => "ARCHIVE_TIMESTAMP",
              "productionTime" => "2026-06-02T12:26:52 +0000",
              "qualification" => "QTS",
              "subjectDN" => "CN=Timestamp Authority",
              "notAfter" => "2030-06-02T12:26:52 +0000"
            }
          ]
        }
      ]
    }

    validation_result = AutogramService.new.send(:parse_validation_response, response)
    signature = validation_result.signatures.first

    assert_equal "2028-06-02T12:25:52 +0000", signature.certificateInfo[:notAfter]
    assert_equal "2030-06-02T12:26:52 +0000", signature.timestampInfo[:timestamps].first.notAfter
  end

  test "parse_validation_response uses a PAdES document timestamp as signing time and qualifies it" do
    response = {
      "signatures" => [
        {
          "validationResult" => "TOTAL_PASSED",
          "level" => "PAdES_BASELINE_T",
          "claimedSigningTime" => "2026-10-01T06:42:32 +0000",
          "signingCertificate" => { "qualification" => "QESIG", "subjectDN" => "CN=Marek" },
          "areQualifiedTimestamps" => true,
          "timestamps" => [
            {
              "timestampType" => "DOCUMENT_TIMESTAMP",
              "productionTime" => "2026-10-01T15:18:31 +0000",
              "qualification" => "QTSA",
              "subjectDN" => "CN=Timestamp Authority"
            }
          ]
        }
      ]
    }

    signature = AutogramService.new.send(:parse_validation_response, response).signatures.first

    assert signature.qualified_timestamps?
    assert_equal "qesig_ts", signature.qualification_label
    assert_equal Time.parse("2026-10-01T15:18:31 +0000"), signature.signingTime
  end

  test "parse_validation_response extracts AGP reference metadata" do
    response = {
      "signatures" => [
        {
          "validationResult" => "TOTAL_PASSED",
          "level" => "PAdES_BASELINE_B",
          "claimedSigningTime" => "2026-06-02T12:25:52 +0000",
          "agpReference" => "PUBLIC-REF-123",
          "agpInstance" => "agp.example.test",
          "signingCertificate" => {
            "qualification" => "QESIG",
            "issuerDN" => "CN=Issuer",
            "subjectDN" => "CN=Autogram Test"
          },
          "areQualifiedTimestamps" => false,
          "timestamps" => []
        }
      ]
    }

    validation_result = AutogramService.new.send(:parse_validation_response, response)
    signature = validation_result.signatures.first

    assert_equal "PUBLIC-REF-123", signature.agpReference
    assert_equal "agp.example.test", signature.agpInstance
  end

  class AutogramValidationResultTest < ActiveSupport::TestCase
    test "qualified? returns true for valid qualified signature" do
      signature = AutogramService::ValidationSignature.new(
        valid: true,
        certificateInfo: { qualification: "QESIG" },
        signerName: "Autogram Test",
        signingTime: "2026-06-02T12:25:52 +0000"
      )

      assert signature.qualified?
    end

    test "qualified? returns false for valid non-qualified signature" do
      signature = AutogramService::ValidationSignature.new(
        valid: true,
        certificateInfo: { qualification: "NA" },
        signerName: "Autogram Test",
        signingTime: "2026-06-02T12:25:52 +0000"
      )

      refute signature.qualified?
    end

    test "qualified? returns false for invalid qualified signature" do
      signature = AutogramService::ValidationSignature.new(
        valid: false,
        certificateInfo: { qualification: "QESIG" },
        signerName: "Autogram Test",
        signingTime: "2026-06-02T12:25:52 +0000"
      )

      refute signature.qualified?
    end

    test "qualification_label returns correct label for adesig qc qc signature" do
      signature = AutogramService::ValidationSignature.new(
        valid: true,
        certificateInfo: { qualification: "ADESIG_QC-QC" },
        signerName: "Autogram Test",
        signingTime: "2026-06-02T12:25:52 +0000"
      )

      assert_equal "adesig_qc_qc", signature.qualification_label
    end

    test "qualification_label returns correct label for adesig qc qc with ts signature" do
      signature = AutogramService::ValidationSignature.new(
        valid: true,
        certificateInfo: { qualification: "ADESIG_QC-QC" },
        timestampInfo: { qualified: true },
        signerName: "Autogram Test",
        signingTime: "2026-06-02T12:25:52 +0000"
      )

      assert_equal "adesig_qc_qc_ts", signature.qualification_label
    end
  end

  test "staging accepts the Autogram test certificate only when ALLOW_TEST_SIGNATURES is set" do
    service = AutogramService.new
    accepted = -> { service.send(:accepted_signature_result?, "INDETERMINATE", AutogramService::TEST_SIGNER_COMMON_NAME) }

    in_rails_env("staging") do
      with_allow_test_signatures(nil) { assert_not accepted.call }
      with_allow_test_signatures("true") { assert accepted.call }
    end

    in_rails_env("production") do
      with_allow_test_signatures("true") { assert_not accepted.call }
    end
  end

  private

  def in_rails_env(name)
    previous = Rails.env
    Rails.env = name
    yield
  ensure
    Rails.env = previous
  end

  def with_allow_test_signatures(value)
    previous = ENV["ALLOW_TEST_SIGNATURES"]
    value.nil? ? ENV.delete("ALLOW_TEST_SIGNATURES") : ENV["ALLOW_TEST_SIGNATURES"] = value
    yield
  ensure
    previous.nil? ? ENV.delete("ALLOW_TEST_SIGNATURES") : ENV["ALLOW_TEST_SIGNATURES"] = previous
  end
end
