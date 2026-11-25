require "prawn"
require "pdf/reader"

# Builds a PDF from photos of signed paper pages and counts PDF pages.
module PaperScan
  IMAGE_TYPES = %w[image/jpeg image/png].freeze
  PDF_TYPE = "application/pdf".freeze

  # images: Array of [bytes, content_type]; one A4 page per image, fit and centered.
  def self.combine(images)
    pdf = Prawn::Document.new(page_size: "A4", margin: 0, skip_page_creation: true)
    images.each do |bytes, _content_type|
      pdf.start_new_page
      pdf.image StringIO.new(bytes), fit: [ pdf.bounds.width, pdf.bounds.height ], position: :center, vposition: :center
    end
    pdf.render
  end

  def self.page_count(pdf_bytes)
    PDF::Reader.new(StringIO.new(pdf_bytes)).page_count
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError
    nil
  end
end
