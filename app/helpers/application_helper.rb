require "rqrcode"

module ApplicationHelper
  def render_inline_code(text)
    fragments = text.to_s.split(/(`[^`]+`)/)

    safe_join(fragments.map do |fragment|
      if fragment.start_with?("`") && fragment.end_with?("`")
        content_tag(
          :code,
          fragment[1..-2],
          class: "rounded bg-gray-100 px-1.5 py-0.5 font-mono text-[0.9em] text-gray-800"
        )
      else
        ERB::Util.html_escape(fragment)
      end
    end)
  end

  def terms_of_service_link
    ENV["TERMS_OF_SERVICE_URL"].presence || root_path
  end

  def privacy_policy_link
    ENV["PRIVACY_POLICY_URL"].presence || root_path
  end

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

  def qr_code_svg(text)
    qr = RQRCode::QRCode.new(text)

    svg = qr.as_svg(
      color: "black",
      shape_rendering: "crispEdges",
      standalone: true,
      use_path: true,
      viewbox: true
    )

    svg.html_safe
  rescue => e
    Rails.logger.error "Failed to generate QR code: #{e.message}"
    %(<svg width="100%" height="100%" xmlns="http://www.w3.org/2000/svg">
      <rect width="100%" height="100%" fill="#f3f4f6"/>
      <text x="50%" y="50%" text-anchor="middle" dy=".3em" fill="#6b7280" font-size="14">QR code not available</text>
    </svg>).html_safe
  end

  def signature_format(level, container)
    return t("signature_parameters.format.pades") if level == "PAdES"

    return t("signature_parameters.format.unknown") unless container.include? "ASiC"

    if level == "XAdES"
      t("signature_parameters.format.xades")
    elsif level == "CAdES"
      t("signature_parameters.format.cades")
    else
      t("signature_parameters.format.unknown")
    end
  end

  def signature_validation_object_name(object)
    raw_name = case object
    when String
      object
    when Hash
      object[:filename] || object["filename"] ||
        object[:name] || object["name"] ||
        object[:path] || object["path"] ||
        object[:value] || object["value"] ||
        signature_validation_object_name(object[:document] || object["document"] || object[:object] || object["object"])
    else
      object.respond_to?(:filename) ? object.filename.to_s : object.to_s
    end

    signature_validation_normalize_object_name(raw_name)
  end

  def signature_validation_signature_documents(signature, validation_result = nil, contract = nil)
    signed_objects = Array(signature.signedObjects)
    if signed_objects.blank? && validation_result&.signatures&.length == 1
      signed_objects = Array(validation_result.document_info[:signed_objects])
    end

    document_names = signed_objects.map { |object| signature_validation_object_name(object) }.compact_blank.uniq
    visible_documents = signature_validation_contract_documents(contract)

    return document_names if visible_documents.blank?

    document_names & visible_documents
  end

  def signature_validation_all_documents_covered?(signature, validation_result, contract = nil)
    covered_documents = signature_validation_signature_documents(signature, validation_result, contract)
    all_documents = signature_validation_result_documents(validation_result, contract)

    covered_documents.any? && all_documents.any? && covered_documents.sort == all_documents.sort
  end

  def signature_validation_multiple_documents?(validation_result, contract = nil)
    signature_validation_result_documents(validation_result, contract).length > 1
  end

  def signature_validation_partially_documents_covered?(signature, validation_result, contract = nil)
    return false unless signature_validation_multiple_documents?(validation_result, contract)

    covered_documents = signature_validation_signature_documents(signature, validation_result, contract)
    all_documents = signature_validation_result_documents(validation_result, contract)

    covered_documents.any? && all_documents.any? && covered_documents.sort != all_documents.sort
  end

  def signature_validation_result_documents(validation_result, contract = nil)
    visible_documents = signature_validation_contract_documents(contract)
    return visible_documents if visible_documents.any?

    document_info = validation_result&.document_info || {}
    Array(document_info[:signed_objects]).map { |object| signature_validation_object_name(object) }.compact_blank +
      Array(document_info[:unsigned_objects]).map { |object| signature_validation_object_name(object) }.compact_blank
  end

  def signature_validation_format_datetime(value)
    return if value.blank?

    parsed_value = case value
    when Time, ActiveSupport::TimeWithZone
      value
    else
      Time.zone.parse(value.to_s)
    end

    parsed_value&.strftime("%d. %b %Y %H:%M:%S")
  rescue ArgumentError
    nil
  end

  def signature_validation_agp_mapping(signature, validation_entry = nil)
    return unless signature.agpReference.present?

    signature_validation_agp_reference_mapping(signature.agpReference, validation_entry&.document_hash)
  end

  def signature_validation_agp_mapping_for_record(record)
    return unless record.agp_reference.present?

    signature_validation_agp_reference_mapping(record.agp_reference, record.document_hash)
  end

  private

  def signature_validation_agp_reference_mapping(agp_reference, document_hash)
    return if agp_reference.blank?

    @signature_validation_agp_mapping_cache ||= {}
    cache_key = [ agp_reference, document_hash ]
    @signature_validation_agp_mapping_cache[cache_key] ||= begin
      evidence_record = SignatureEvidenceRecord
        .includes(:session, contract_content_version: [ :contract, :contract_validation_record ])
        .find_by(public_reference: agp_reference)

      expected_document_hash = signature_validation_evidence_document_hash(evidence_record)

      {
        evidence_record: evidence_record,
        document_hash_matches: expected_document_hash.present? && document_hash.present? ? expected_document_hash == document_hash : nil
      }
    end
  end

  def signature_validation_contract_documents(contract)
    Array(contract&.documents).map { |document| signature_validation_object_name(document.filename) }.compact_blank.uniq
  end

  def signature_validation_normalize_object_name(name)
    value = name.to_s.strip
    return if value.blank?

    value.split(/[\\\/]/).last
  end

  def signature_validation_evidence_document_hash(evidence_record)
    return if evidence_record.blank?

    stored_validation_record = evidence_record.contract_content_version&.contract_validation_record
    return stored_validation_record.document_hash if stored_validation_record.present?

    content_version = evidence_record.contract_content_version
    return if content_version.blank?

    Digest::SHA256.hexdigest(content_version.content)
  rescue StandardError
    nil
  end
end
