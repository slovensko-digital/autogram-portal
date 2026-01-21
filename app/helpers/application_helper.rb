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

  def signature_format(level, container)
    return t("helpers.application.signature_levels.pades") if level == "PAdES"

    return t("helpers.application.signature_levels.unknown") unless container.include? "ASiC"

    if level == "XAdES"
      t("helpers.application.signature_levels.xades_asice")
    elsif level == "CAdES"
      t("helpers.application.signature_levels.cades_asice")
    else
      t("helpers.application.signature_levels.unknown")
    end
  end

  def signature_qualification(qualification, timestamp)
    if timestamp
      case qualification
      when "QESIG"
        t("helpers.application.signature_qualifications.qesig_ts")
      when "QESEAL"
        t("helpers.application.signature_qualifications.qeseal_ts")
      when "ADESIG_QC-QC"
        t("helpers.application.signature_qualifications.adesig_qc_qc_ts")
      else
        t("helpers.application.signature_qualifications.unknown")
      end
    else
      case qualification
      when "QESIG"
        t("helpers.application.signature_qualifications.qesig")
      when "QESEAL"
        t("helpers.application.signature_qualifications.qeseal")
      when "ADESIG_QC-QC"
        t("helpers.application.signature_qualifications.adesig_qc_qc")
      else
        t("helpers.application.signature_qualifications.unknown")
      end
    end
  end
end
