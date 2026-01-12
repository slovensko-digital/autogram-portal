require "rqrcode"

module ApplicationHelper
  def decode_base64_content(content, mime_type)
    return content unless mime_type&.include?(";base64")

    if mime_type.include?("text/")
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

    svg = qr.as_svg(
      color: "1e40af",
      shape_rendering: "crispEdges",
      module_size: size / qr.modules.count,
      standalone: true,
      use_path: true
    )

    svg.html_safe
  rescue => e
    Rails.logger.error "Failed to generate QR code: #{e.message}"
    %(<svg width="#{size}" height="#{size}" xmlns="http://www.w3.org/2000/svg">
      <rect width="100%" height="100%" fill="#f3f4f6"/>
      <text x="50%" y="50%" text-anchor="middle" dy=".3em" fill="#6b7280" font-size="14">QR code not available</text>
    </svg>).html_safe
  end

  def method_label(method)
    key = method.gsub("-", "_")
    I18n.t("signature_methods.#{key}", default: method.humanize)
  end

  def short_method_label(method)
    key = method.gsub("-", "_")
    I18n.t("signature_methods.short.#{key}", default: method.humanize)
  end
end
