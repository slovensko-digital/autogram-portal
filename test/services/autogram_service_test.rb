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

    assert_equal [ "document.xdcf", "PdfDocument.pdf", "TextDocument.txt" ], validation_result.signatures.first[:signed_objects].map { |object| object["filename"] }
    assert_equal [ "PdfDocument.pdf" ], validation_result.signatures.second[:signed_objects].map { |object| object["filename"] }
  end
end
