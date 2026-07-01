class AutogramService
  AUTOGRAM_BASE_URL = ENV.fetch("AUTOGRAM_SERVICE_URL", "http://localhost:7200")
  TEST_SIGNER_COMMON_NAME = "Autogram Test".freeze
  EXTENSION_LEVELS = %w[T LT LTA].freeze
  VALIDATION_READ_RETRIES = 3
  VALIDATION_READ_RETRY_DELAY = 0.05

  class ValidationResult
    attr_reader :hasSignatures, :signatures, :errors, :documentInfo

    def initialize(hasSignatures:, signatures: [], errors: [], documentInfo: {})
      @hasSignatures = hasSignatures
      @signatures = signatures
      @errors = errors
      @documentInfo = documentInfo
    end

    def valid_response?
      @errors.empty?
    end

    def signature_count
      @signatures.length
    end

    def has_signatures?
      @hasSignatures
    end
  end

  class ValidationSignature
    attr_reader :signerName, :signingTime, :signatureLevel, :validationResult, :valid, :signedObjects, :unsignedObjects, :certificateInfo, :timestampInfo

    def initialize(signerName:, signingTime: nil, signatureLevel: nil, validationResult: nil, valid: false, signedObjects: [], unsignedObjects: [], certificateInfo: {}, timestampInfo: nil)
      @signerName = signerName
      @signingTime = signingTime
      @signatureLevel = signatureLevel
      @validationResult = validationResult
      @valid = valid
      @signedObjects = signedObjects
      @unsignedObjects = unsignedObjects
      @certificateInfo = certificateInfo
      @timestampInfo = timestampInfo
    end

    def qualified?
      valid && certificateInfo[:qualification].to_s.in?(%w[QESIG QESEAL])
    end

    def adesig_qc?
      valid && certificateInfo[:qualification].to_s == "ADESIG_QC-QC"
    end

    def qualified_timestamps?
      timestampInfo && timestampInfo[:qualified] == true
    end

    def qualification_label
      qualification = certificateInfo[:qualification]
      timestamp = qualified_timestamps?
      if timestamp
        case qualification
        when "QESIG"
          "qesig_ts"
        when "QESEAL"
          "qeseal_ts"
        when "ADESIG_QC-QC"
          "adesig_qc_qc_ts"
        else
          "unknown"
        end
      else
        case qualification
        when "QESIG"
          "qesig"
        when "QESEAL"
          "qeseal"
        when "ADESIG_QC-QC"
          "adesig_qc_qc"
        else
          "unknown"
        end
      end
    end
  end

  class ValidationTimestamp
    attr_reader :type, :time, :qualification, :subject, :notAfter

    def initialize(type:, time:, qualification: nil, subject: nil, notAfter: nil)
      @type = type
      @time = time
      @qualification = qualification
      @subject = subject
      @notAfter = notAfter
    end

    def qualified?
      qualification.to_s == "QTS"
    end
  end

  def validate_signatures(document)
    return error_result("Súbor nie je pripojený") unless document.blob.attached?

    begin
      file_content = Base64.strict_encode64(read_document_content_with_retry(document))
      response = call_autogram_validate_api(file_content)

      if response.success?
        parse_validation_response(response.body)
      elsif response.status == 422 && response.body["code"] == "DOCUMENT_NOT_SIGNED"
        ValidationResult.new(hasSignatures: false)
      else
        error_result("Error communicating with Autogram service: #{response.status}")
      end
    rescue StandardError => e
      error_result("Error communicating with Autogram service: #{e.class}: #{e.message}")
    end
  end

  def visualize_document(document)
    return error_result("Súbor nie je pripojený") unless document.blob.attached?

    begin
      file_content = Base64.strict_encode64(document.content)
      response = call_autogram_visualization_api(file_content, document)

      if response.success?
        parse_visualization_response(response.body)
      else
        error_result("Error communicating with Autogram service: #{response.status}: #{response.body}")
      end
    rescue StandardError => e
      error_result("Error communicating with Autogram service: #{e.class}: #{e.message}")
    end
  end

  def stamp_pdf(document, stamp:)
    return nil if document.content.nil?

    file_content = Base64.strict_encode64(document.content)
    response = call_autogram_stamp_pdf_api(file_content, document, stamp: stamp)

    if response.success?
      data = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)
      return Base64.strict_decode64(data["content"])
    end

    raise AutogramServiceError, "Error communicating with Autogram service: #{response.status}: #{response.body}"
  rescue StandardError => e
    Rails.logger.warn "Autogram stamp PDF service not available: #{e.message}"
    raise ServiceUnavailableError
  end

  def prepare_signature_fields(document, fields:)
    return nil if document.content.nil?

    file_content = Base64.strict_encode64(document.content)
    response = call_autogram_prepare_signature_fields_api(file_content, document, fields: fields)

    if response.success?
      data = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)
      return Base64.strict_decode64(data["content"])
    end

    raise AutogramServiceError, "Error communicating with Autogram service: #{response.status}: #{response.body}"
  rescue StandardError => e
    Rails.logger.warn "Autogram prepare signature fields service not available: #{e.message}"
    raise ServiceUnavailableError
  end

  class AutogramServiceError < StandardError
    def message
      I18n.t("autogram_service.errors.#{self.class.name.demodulize.underscore}", default: super)
    end
  end
  class CertificateExpiredError < AutogramService::AutogramServiceError; end
  class ServiceUnavailableError < AutogramService::AutogramServiceError; end
  class UnknownResponseError < AutogramService::AutogramServiceError; end
  class DocumentMismatchError < AutogramService::AutogramServiceError; end

  def extend_signatures(document, target_level: "T")
    return nil if document.content.nil?

    file_content = Base64.strict_encode64(document.content)
    begin
      response = call_autogram_extend_api(file_content, target_level: target_level)
    rescue StandardError => e
      Rails.logger.warn "Autogram extend signatures service not available: #{e.message}"
      raise ServiceUnavailableError
    end

    if response.success?
      begin
        data = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)
        return Base64.decode64(data["content"])
      rescue StandardError => e
        raise UnknownResponseError
      end
    end

    if response.status == 422 && response.body["code"] == "CERTIFICATE_EXPIRED"
      raise CertificateExpiredError
    end

    raise ServiceUnavailableError
  end

  def ensure_documents_equal(old:, new:)
    old_content = old.map { Base64.strict_encode64(read_document_content_with_retry(it)) }
    new_content = Base64.strict_encode64(read_document_content_with_retry(new))

    begin
      response = call_autogram_compare_api(old_content, new_content)
    rescue StandardError => e
      Rails.logger.warn "Autogram compare documents service not available: #{e.message}"
      raise ServiceUnavailableError
    end

    raise DocumentMismatchError unless response.success?

    data = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)
    raise DocumentMismatchError unless data["contentMatches"] == true && data["allSignaturesPreserved"] == true
  rescue JSON::ParserError => e
    raise UnknownResponseError
  end

  private

  def call_autogram_validate_api(file_content)
    connection = Faraday.new(url: AUTOGRAM_BASE_URL) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    payload = {
      content: file_content
    }

    connection.post("/validate", payload)
  end

  def call_autogram_visualization_api(file_content, document)
    connection = Faraday.new(url: AUTOGRAM_BASE_URL) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    payload = {
      document: {
        content: file_content
      },
      parameters: {
        autoLoadEform: true,
        level: document.is_pdf? ? "PAdES_BASELINE_B" : "XAdES_BASELINE_B",
        fsFormId: document.xdc_parameters&.fs_form_identifier
      },
      payloadMimeType: determine_payload_mime_type(document)
    }

    connection.post("/visualization", payload)
  end

  def call_autogram_stamp_pdf_api(file_content, document, stamp:)
    connection = Faraday.new(url: AUTOGRAM_BASE_URL) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    payload = {
      document: {
        filename: document.filename,
        content: file_content,
        mimeType: determine_payload_mime_type(document)
      },
      stamp: stamp
    }

    connection.post("/stamp-pdf", payload)
  end

  def call_autogram_extend_api(file_content, target_level: "T")
    connection = Faraday.new(url: AUTOGRAM_BASE_URL) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    normalized_target_level = target_level.to_s.upcase
    raise ArgumentError, "Unsupported target level: #{target_level}" unless EXTENSION_LEVELS.include?(normalized_target_level)

    payload = {
      targetLevel: normalized_target_level,
      document: {
        content: file_content
      }
    }

    connection.post("/extend", payload)
  end

  def call_autogram_prepare_signature_fields_api(file_content, document, fields:)
    connection = Faraday.new(url: AUTOGRAM_BASE_URL) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    payload = {
      document: {
        filename: document.filename,
        content: file_content,
        mimeType: determine_payload_mime_type(document)
      },
      fields: fields
    }

    connection.post("/prepare-signature-fields", payload)
  end

  def call_autogram_compare_api(old_content, new_content)
    connection = Faraday.new(url: AUTOGRAM_BASE_URL) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    payload = {
      originalDocuments: old_content.map { |content| { content: content } },
      signedDocument: { content: new_content }
    }

    connection.post("/validate-signed-version", payload)
  end

  def parse_validation_response(response_body)
    data = response_body.is_a?(Hash) ? response_body : JSON.parse(response_body)

    signatures_data = data["signatures"]
    signed_objects = data["signedObjects"] || []
    unsigned_objects = data["unsignedObjects"] || []

    has_signatures = signatures_data.present?
    signatures = has_signatures ? signatures_data.map { |sig| parse_signature_info(sig, data) } : []

    ValidationResult.new(
      hasSignatures: has_signatures,
      signatures: signatures,
      documentInfo: {
        containerType: data["containerType"],
        signatureForm: data["signatureForm"],
        signedObjectsCount: signed_objects.length,
        unsignedObjectsCount: unsigned_objects.length,
        signedObjects: signed_objects,
        unsignedObjects: unsigned_objects
      }
    )
  rescue JSON::ParserError => e
    error_result("Nepodarilo sa spracovať odpoveď zo služby: #{e.message}")
  end

  def parse_visualization_response(response_body)
    data = response_body.is_a?(Hash) ? response_body : JSON.parse(response_body)

    {
      content: data["content"],
      mime_type: data["mimeType"],
      filename: data["filename"]
    }
  rescue JSON::ParserError => e
    error_result("Nepodarilo sa spracovať odpoveď zo služby: #{e.message}")
  end

  def determine_payload_mime_type(document)
    document.content_type + "; base64"
  end

  def parse_signature_info(signatures_data, value_data)
    signing_cert = signatures_data["signingCertificate"] || {}
    timestamps = signatures_data["timestamps"] || []
    signed_objects = resolve_signature_objects(signatures_data, value_data, "signedObjects")
    unsigned_objects = resolve_signature_objects(signatures_data, value_data, "unsignedObjects")

    subject_dn = signing_cert["subjectDN"] || ""
    signer_name = extract_cn_from_dn(subject_dn)
    validation_result = signatures_data["validationResult"]

    first_timestamp = timestamps.find { |ts| ts["timestampType"] == "SIGNATURE_TIMESTAMP" }
    signing_time = if first_timestamp
      Time.parse(first_timestamp["productionTime"])
    elsif signatures_data["claimedSigningTime"]
      Time.parse(signatures_data["claimedSigningTime"])
    else
      nil
    end

    has_qualified_timestamps = signatures_data["areQualifiedTimestamps"]

    ValidationSignature.new(
      signerName: signer_name,
      signingTime: signing_time,
      signatureLevel: signatures_data["level"]&.gsub(/[XPC]AdES_/, ""),
      validationResult: validation_result,
      valid: accepted_signature_result?(validation_result, signer_name),
      certificateInfo: {
        subject: signing_cert["subjectDN"],
        issuer: signing_cert["issuerDN"],
        qualification: signing_cert["qualification"],
        notAfter: signing_cert["notAfter"]
      },
      signedObjects: signed_objects,
      unsignedObjects: unsigned_objects,
      timestampInfo: has_qualified_timestamps && timestamps.any? ? {
        count: timestamps.length,
        qualified: has_qualified_timestamps,
        timestamps: timestamps.map do |ts|
          ValidationTimestamp.new(
            type: ts["timestampType"],
            time: Time.parse(ts["productionTime"]),
            qualification: ts["qualification"],
            subject: ts["subjectDN"],
            notAfter: ts["notAfter"]
          )
        end
      } : nil
    )
  end

  def resolve_signature_objects(signatures_data, value_data, key)
    objects = signatures_data[key] || []
    return objects if objects.present?

    object_ids = signatures_data["#{key}Ids"] || []
    return [] if object_ids.blank?

    object_index = Array(value_data["signedObjects"]).concat(Array(value_data["unsignedObjects"])).index_by { |object| object["id"] }
    object_ids.filter_map { |object_id| object_index[object_id] }
  end

  def read_document_content_with_retry(document)
    attempts = 0

    begin
      attempts += 1
      document.content
    rescue ActiveStorage::FileNotFoundError, Errno::ENOENT
      raise if attempts >= VALIDATION_READ_RETRIES

      sleep(VALIDATION_READ_RETRY_DELAY * attempts)
      retry
    end
  end

  def extract_cn_from_dn(dn)
    match = dn.match(/CN=([^,]+)/)
    match ? match[1].strip : dn
  end

  # The public dev signing flow uses the Autogram test certificate, which the
  # validation service reports as INDETERMINATE because it is not publicly trusted.
  # Accept it only in local/test environments so embedded signing can be exercised.
  def accepted_signature_result?(validation_result, signer_name)
    return true if validation_result == "TOTAL_PASSED"
    return false unless allow_indeterminate_test_signatures?

    validation_result == "INDETERMINATE" && signer_name == TEST_SIGNER_COMMON_NAME
  end

  def allow_indeterminate_test_signatures?
    Rails.env.development? || Rails.env.test?
  end

  def error_result(message)
    ValidationResult.new(
      hasSignatures: false,
      errors: [ message ]
    )
  end
end
