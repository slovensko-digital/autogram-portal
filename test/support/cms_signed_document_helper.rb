# Builds documents signed in an enveloping CMS (CAdES) and validates them like the Autogram service does.
module CmsSignedDocumentHelper
  SIGNED_PDF_CONTENT = "%PDF-1.4 signed inside CMS".b.freeze

  def cms_signed_content(content = SIGNED_PDF_CONTENT, detached: false)
    key = OpenSSL::PKey::RSA.new(2048)
    certificate = OpenSSL::X509::Certificate.new
    certificate.version = 2
    certificate.serial = 1
    certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse("/CN=Autogram Test")
    certificate.public_key = key
    certificate.not_before = 1.hour.ago
    certificate.not_after = 1.hour.from_now
    certificate.sign(key, "SHA256")

    flags = OpenSSL::PKCS7::BINARY
    flags |= OpenSSL::PKCS7::DETACHED if detached
    OpenSSL::PKCS7.sign(certificate, key, content, [], flags).to_der
  end

  # Browsers and Marcel take an enveloping CMS with a PDF inside for a PDF.
  def cms_signed_upload(filename = "pdf_cades.pdf", content_type: "application/pdf")
    Rack::Test::UploadedFile.new(StringIO.new(cms_signed_content), content_type, true, original_filename: filename)
  end

  def with_cms_validation_service(&block)
    with_validation_service(CmsValidationService.new, &block)
  end

  def with_validation_service(service)
    environment_singleton = AutogramEnvironment.singleton_class
    environment_singleton.send(:alias_method, :__original_autogram_service, :autogram_service)
    environment_singleton.send(:define_method, :autogram_service) { service }

    yield
  ensure
    environment_singleton.send(:remove_method, :autogram_service)
    environment_singleton.send(:alias_method, :autogram_service, :__original_autogram_service)
    environment_singleton.send(:remove_method, :__original_autogram_service)
  end

  class CmsValidationService
    def validate_signatures(document)
      return AutogramService::ValidationResult.new(hasSignatures: false) unless CmsSignedDocumentExtractor.new(document.content, filename: document.filename).cms_signed?

      AutogramService::ValidationResult.new(
        hasSignatures: true,
        signatures: [
          AutogramService::ValidationSignature.new(
            signerName: "Autogram Test",
            signingTime: Time.utc(2026, 10, 7, 7, 41, 58),
            signatureLevel: "BASELINE_B",
            validationResult: "TOTAL_PASSED",
            valid: true,
            certificateInfo: { subject: "CN=Autogram Test", issuer: "CN=Autogram Test", qualification: "QESIG" },
            signedObjects: [ { "id" => "D-1", "mimeType" => "application/pdf" } ]
          )
        ],
        documentInfo: {
          containerType: nil,
          signatureForm: "CAdES",
          signedObjectsCount: 1,
          unsignedObjectsCount: 0,
          signedObjects: [ { "id" => "D-1", "mimeType" => "application/pdf" } ],
          unsignedObjects: []
        }
      )
    end
  end
end
