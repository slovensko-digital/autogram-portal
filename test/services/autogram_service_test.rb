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
end
