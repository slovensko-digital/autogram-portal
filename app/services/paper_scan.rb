require "prawn"
require "pdf/reader"

# Builds a PDF from photos of signed paper pages and counts PDF pages.
module PaperScan
  IMAGE_TYPES = %w[image/jpeg image/png].freeze
  PDF_TYPE = "application/pdf".freeze

  # Prawn embeds a JPEG as it is but inflates the whole image data of a PNG into memory, so a small
  # PNG can take gigabytes on submit. Photos from the browser arrive downsized as JPEG; a PNG page
  # needs no more than this.
  MAX_PNG_PIXELS = 12_000_000
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b
  PNG_CHANNELS = { 0 => 1, 2 => 3, 3 => 1, 4 => 2, 6 => 4 }.freeze
  READ_SLICE = 64.kilobytes

  # images: Array of [bytes, content_type]; one A4 page per image, fit and centered.
  def self.combine(images)
    pdf = Prawn::Document.new(page_size: "A4", margin: 0, skip_page_creation: true)
    images.each do |bytes, _content_type|
      pdf.start_new_page
      pdf.image StringIO.new(bytes), fit: [ pdf.bounds.width, pdf.bounds.height ], position: :center, vposition: :center
    end
    pdf.render
  end

  # nil when the PDF cannot be read. Scans are untrusted uploads and the count only drives a
  # warning, so any parser failure means "unknown".
  def self.page_count(pdf_bytes)
    PDF::Reader.new(StringIO.new(pdf_bytes)).page_count
  rescue StandardError
    nil
  end

  # Why Prawn must not read the PNG in +io+, as a PaperSignature::InvalidUpload reason, or nil.
  # Prawn takes the size from any IHDR chunk and inflates all IDAT data at once, so the header must
  # be the first and only one, within MAX_PNG_PIXELS, and the data must not inflate to more than the
  # header declares. The data is inflated here in slices and thrown away, so a compressed bomb is
  # stopped early. A file damaged in other ways is left to Prawn, which refuses it on submit.
  def self.png_problem(io)
    io.rewind
    return :unsupported_file unless io.read(8) == PNG_SIGNATURE
    return :unsupported_file unless io.read(8).to_s.unpack("Na4") == [ 13, "IHDR" ]

    header = io.read(13).to_s
    return :unsupported_file unless header.bytesize == 13

    width, height, bits, color_type = header.unpack("NNCC")
    channels = PNG_CHANNELS[color_type]
    return :unsupported_file unless width.positive? && height.positive? && bits.positive? && channels
    return :image_too_large if width * height > MAX_PNG_PIXELS

    declared = height * (1 + ((width * channels * bits) + 7) / 8)
    inflated = 0
    inflater = Zlib::Inflate.new
    read_slices(io, 4) # CRC

    loop do
      chunk_header = io.read(8).to_s
      break if chunk_header.bytesize < 8

      length, type = chunk_header.unpack("Na4")
      break if type == "IEND"
      return :unsupported_file if type == "IHDR"

      read_slices(io, length) do |slice|
        next unless type == "IDAT"

        inflater.inflate(slice) do |data|
          inflated += data.bytesize
          return :unsupported_file if inflated > declared
        end
      end
      read_slices(io, 4) # CRC
    end

    nil
  rescue Zlib::Error
    :unsupported_file
  ensure
    inflater&.close
    io.rewind
  end

  # Reads +length+ bytes in slices, so a chunk that claims gigabytes costs no memory. Uploaded files
  # cannot seek.
  def self.read_slices(io, length)
    while length.positive?
      slice = io.read([ length, READ_SLICE ].min)
      break if slice.nil?

      length -= slice.bytesize
      yield slice if block_given?
    end
  end
  private_class_method :read_slices
end
