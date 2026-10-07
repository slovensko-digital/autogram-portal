# Reads the document signed inside an enveloping CMS signature (CAdES), e.g. a PDF wrapped in a .p7m file
# that is sometimes still named .pdf. Signatures are verified by the validation service, not here.
class CmsSignedDocumentExtractor
  CONTENT_TYPE = "application/pkcs7-mime".freeze
  SIGNATURE_EXTENSIONS = %w[ .p7m .p7s ].freeze

  def initialize(content, filename:)
    @content = content
    @filename = filename.to_s
  end

  def cms_signed?
    signed_content.present?
  end

  def signed_content
    return @signed_content if defined?(@signed_content)

    @signed_content = read_signed_content
  end

  def signed_filename
    extension = File.extname(filename)
    return filename unless SIGNATURE_EXTENSIONS.include?(extension.downcase)

    File.basename(filename, extension).presence || filename
  end

  def signed_content_type
    Marcel::MimeType.for(StringIO.new(signed_content), name: signed_filename)
  end

  private

  attr_reader :content, :filename

  def read_signed_content
    # Every CMS structure is a DER SEQUENCE; skip parsing anything else.
    return unless content&.start_with?("\x30".b)

    pkcs7 = OpenSSL::PKCS7.new(content)
    return unless pkcs7.type == :signed && !pkcs7.detached?

    # Without verification OpenSSL only extracts the encapsulated content.
    pkcs7.verify([], OpenSSL::X509::Store.new, nil, OpenSSL::PKCS7::NOVERIFY | OpenSSL::PKCS7::NOSIGS)
    pkcs7.data.presence
  rescue ArgumentError, OpenSSL::PKCS7::PKCS7Error
    nil
  end
end
