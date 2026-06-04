class AutogramService
  AUTOGRAM_BASE_URL = ENV.fetch("AUTOGRAM_SERVICE_URL", "http://localhost:7200")
  TEST_SIGNER_COMMON_NAME = "Autogram Test".freeze
  EXTENSION_LEVELS = %w[T LT LTA].freeze

  class ValidationResult
    attr_reader :has_signatures, :signatures, :errors, :document_info

    def initialize(has_signatures:, signatures: [], errors: [], document_info: {})
      @has_signatures = has_signatures
      @signatures = signatures
      @errors = errors
      @document_info = document_info
    end

    def valid_response?
      @errors.empty?
    end

    def signature_count
      @signatures.length
    end
  end

  def validate_signatures(document)
    return error_result("Súbor nie je pripojený") unless document.blob.attached?

    begin
      file_content = Base64.strict_encode64(document.content)
      response = call_autogram_validate_api(file_content)

      if response.success?
        parse_validation_response(response.body)
      elsif response.status == 422 && response.body["code"] == "DOCUMENT_NOT_SIGNED"
        ValidationResult.new(has_signatures: false)
      else
        error_result("Error communicating with Autogram service: #{response.status}")
      end
    rescue StandardError => e
      error_result("Error communicating with Autogram service: #{e.message}")
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
        error_result("Error communicating with Autogram service: #{response.status}")
      end
    rescue StandardError => e
      error_result("Error communicating with Autogram service: #{e.message}")
    end
  end

  def extend_signatures(document, target_level: "T")
    return nil if document.content.nil?

    begin
      file_content = Base64.strict_encode64(document.content)
      response = call_autogram_extend_api(file_content, target_level: target_level)

      raise "Error communicating with Autogram service: #{response.status}" unless response.success?

      data = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)
      Base64.decode64(data["content"])

    rescue StandardError => e
      Rails.logger.warn "Autogram extend signatures service not available: #{e.message}"
      nil
    end
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

  def parse_validation_response(response_body)
    data = response_body.is_a?(Hash) ? response_body : JSON.parse(response_body)

    signatures_data = data["signatures"]
    signed_objects = data["signedObjects"] || []
    unsigned_objects = data["unsignedObjects"] || []

    has_signatures = signatures_data.present?
    signatures = has_signatures ? signatures_data.map { |sig| parse_signature_info(sig, data) } : []

    ValidationResult.new(
      has_signatures: has_signatures,
      signatures: signatures,
      document_info: {
        container_type: data["containerType"],
        signature_form: data["signatureForm"],
        signed_objects_count: signed_objects.length,
        unsigned_objects_count: unsigned_objects.length,
        signed_objects: signed_objects,
        unsigned_objects: unsigned_objects
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

    {
      signer_name: signer_name,
      signing_time: signing_time,
      signature_level: signatures_data["level"]&.gsub(/[XPC]AdES_/, ""),
      validation_result: validation_result,
      valid: accepted_signature_result?(validation_result, signer_name),
      certificate_info: {
        subject: signing_cert["subjectDN"],
        issuer: signing_cert["issuerDN"],
        qualification: signing_cert["qualification"]
      },
      timestamp_info: has_qualified_timestamps && timestamps.any? ? {
        count: timestamps.length,
        qualified: has_qualified_timestamps,
        timestamps: timestamps.map do |ts|
          {
            type: ts["timestampType"],
            time: Time.parse(ts["productionTime"]),
            qualification: ts["qualification"],
            subject: ts["subjectDN"],
            not_after: ts["notAfter"]
          }
        end
      } : nil
    }
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
      has_signatures: false,
      errors: [ message ]
    )
  end
end
