module QrCodeHelper
  # An inline SVG QR code of a URL (signing apps, the phone link of a paper signature). It scales with
  # its container (viewBox) and is hidden from assistive technology; the container describes it.
  # A lower error correction level (e.g. :m) keeps a long URL readable in a small code on a screen.
  def qr_code_svg(url, level: :h)
    svg = RQRCode::QRCode.new(url, level: level).as_svg(module_size: 4, standalone: true, use_path: true, viewbox: true)

    svg.sub("<svg", '<svg aria-hidden="true" focusable="false"').html_safe
  rescue => e
    Rails.logger.error "Failed to generate QR code: #{e.message}"
    %(<svg width="100%" height="100%" xmlns="http://www.w3.org/2000/svg">
      <rect width="100%" height="100%" fill="#f3f4f6"/>
      <text x="50%" y="50%" text-anchor="middle" dy=".3em" fill="#6b7280" font-size="14">QR code not available</text>
    </svg>).html_safe
  end
end
