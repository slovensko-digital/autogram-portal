require "test_helper"
require_relative "../support/cms_signed_document_helper"

class CmsSignedDocumentExtractorTest < ActiveSupport::TestCase
  include CmsSignedDocumentHelper

  test "reads the document signed inside an enveloping CMS" do
    extractor = CmsSignedDocumentExtractor.new(cms_signed_content, filename: "pdf_cades.pdf")

    assert extractor.cms_signed?
    assert_equal SIGNED_PDF_CONTENT, extractor.signed_content
    assert_equal "pdf_cades.pdf", extractor.signed_filename
    assert_equal "application/pdf", extractor.signed_content_type
  end

  test "drops the signature extension from the signed document name" do
    assert_equal "contract.pdf", CmsSignedDocumentExtractor.new(cms_signed_content, filename: "contract.pdf.P7M").signed_filename
    assert_equal "contract", CmsSignedDocumentExtractor.new(cms_signed_content, filename: "contract.p7m").signed_filename
  end

  test "ignores detached signatures and other documents" do
    assert_not CmsSignedDocumentExtractor.new(cms_signed_content(detached: true), filename: "contract.p7s").cms_signed?
    assert_not CmsSignedDocumentExtractor.new("%PDF-1.4 plain".b, filename: "contract.pdf").cms_signed?
    assert_not CmsSignedDocumentExtractor.new("0 not a signature", filename: "contract.txt").cms_signed?
    assert_not CmsSignedDocumentExtractor.new(nil, filename: nil).cms_signed?
  end
end
