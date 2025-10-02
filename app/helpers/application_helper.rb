require 'rqrcode'

module ApplicationHelper
  def decode_base64_content(content, mime_type)
    return content unless mime_type&.include?(";base64")

    if mime_type.include?("text/")
      # For text content, handle UTF-8 encoding properly
      Base64.strict_decode64(content).force_encoding("UTF-8")
    else
      Base64.strict_decode64(content)
    end
  rescue => e
    Rails.logger.error "Failed to decode base64 content: #{e.message}"
    content
  end

  def qr_code_svg(text, size: 200)
    qr = RQRCode::QRCode.new(text)

    # Generate SVG with custom styling
    svg = qr.as_svg(
      color: "1e40af",  # Blue color to match the design
      shape_rendering: "crispEdges",
      module_size: size / qr.modules.count,
      standalone: true,
      use_path: true
    )

    # Mark as html_safe so Rails doesn't escape it
    svg.html_safe
  rescue => e
    Rails.logger.error "Failed to generate QR code: #{e.message}"
    # Return a fallback SVG
    %(<svg width="#{size}" height="#{size}" xmlns="http://www.w3.org/2000/svg">
      <rect width="100%" height="100%" fill="#f3f4f6"/>
      <text x="50%" y="50%" text-anchor="middle" dy=".3em" fill="#6b7280" font-size="14">QR kód nedostupný</text>
    </svg>).html_safe
  end

  def method_label(method)
    case method
    when "qes"
      "Kvalifikovaný elektronický podpis"
    when "ts-qes"
      "Kvalifikovaný elektronický podpis s časovou pečiatkou"
    when "ades"
      "Pokročilý elektronický podpis"
    when "ses"
      "Jednoduchý elektronický podpis"
    else
      method.humanize
    end
  end

  def short_method_label(method)
    case method
    when "qes"
      "Kvalifikovaný"
    when "ts-qes"
      "Kvalifikovaný + časová pečiatka"
    when "ades"
      "Pokročilý"
    when "ses"
      "Jednoduchý"
    else
      method.humanize
    end
  end
end
