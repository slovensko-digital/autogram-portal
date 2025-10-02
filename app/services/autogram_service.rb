class AutogramService
  AUTOGRAM_BASE_URL = ENV.fetch("AUTOGRAM_BASE_URL", "http://localhost:7200")
  AVM_BASE_URL = "https://autogram.slovensko.digital" # Replace with actual AVM API URL

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
      # Prepare the file data for the API call
      file_content = Base64.strict_encode64(document.content)

      # Call the Autogram service
      response = call_autogram_validate_api(file_content)

      if response.success?
        parse_validation_response(response.body)
      elsif response.status == 422 && response.body["code"] == "DOCUMENT_NOT_SIGNED"
        ValidationResult.new(has_signatures: false)
      else
        error_result("Chyba komunikácie s Autogram službou: #{response.status}")
      end
    rescue StandardError => e
      return error_result("Chyba komunikácie s Autogram službou") if Rails.env.production?

      # Fallback to mock data if service is not available
      Rails.logger.warn "Autogram service not available, using mock data: #{e.message}"
      mock_validation_result(document)
    end
  end

  def visualize_document(document)
    return error_result("Súbor nie je pripojený") unless document.blob.attached?

    begin
      # Prepare the file data for the API call
      file_content = Base64.strict_encode64(document.content)

      # Call the Autogram visualization service
      response = call_autogram_visualization_api(file_content, document)

      if response.success?
        parse_visualization_response(response.body)
      else
        error_result("Chyba komunikácie s Autogram službou: #{response.status}")
      end
    rescue StandardError => e
      return error_result("Chyba komunikácie s Autogram službou") if Rails.env.production?

      # Fallback to mock data if service is not available
      Rails.logger.warn "Autogram visualization service not available, using mock data: #{e.message}"
      mock_visualization_result(document)
    end
  end

  # AVM (Autogram Mobile) Signing Methods
  def initiate_avm_signing(contract)
    begin
      # Get the first document from the contract for signing
      document = contract.documents.first
      return { error: "Žiadny dokument na podpísanie" } unless document&.blob&.attached?

      # Prepare document data for AVM service
      file_content = Base64.strict_encode64(document.content)

      payload = {
        document: {
          content: file_content,
          filename: document.filename
        },
        parameters: format_signature_parameters_for_avm(contract.signature_parameters),
        payloadMimeType: document.content_type + "; base64"
      }

      puts "Payload for AVM initiate: #{payload.inspect}"

      secret_key = CGI.escape(Base64.strict_encode64(SecureRandom.random_bytes(32)))
      puts "Generated secret key: #{secret_key}"

      response = call_avm_initiate_api(payload, secret_key)

      if response.success?
        parse_avm_initiate_response(response, secret_key)
      else
        { error: "Chyba komunikácie s AVM službou: #{response.status}" }
      end
    rescue StandardError => e
      return { error: "Chyba komunikácie s AVM službou" } if Rails.env.production?

      # Fallback to mock data if service is not available
      Rails.logger.warn "AVM service not available, using mock data: #{e.message}"
      mock_avm_initiate_result
    end
  end

  def check_avm_signing_status(document_id, if_modified_since, encryption_key)
    begin
      response = call_avm_status_api(document_id, if_modified_since, encryption_key)

      if response.status < 400
        parse_avm_status_response(response)
      else
        { status: 'failed', error: "Chyba komunikácie s AVM službou: #{response.status}" }
      end
    rescue StandardError => e
      return { status: 'failed', error: "Chyba komunikácie s AVM službou" } if Rails.env.production?

      # Mock implementation for development
      Rails.logger.warn "AVM service not available, using mock status: #{e.message}"
      mock_avm_status_result
    end
  end

  def download_avm_signed_document(document_id, encryption_key)
    begin
      response = call_avm_download_api(document_id, encryption_key)

      if response.success?
        parse_avm_download_response(response.body)
      else
        raise "Chyba pri sťahovaní podpísaného dokumentu: #{response.status}"
      end
    rescue StandardError => e
      return mock_signed_document_content if !Rails.env.production?

      raise "Chyba komunikácie s AVM službou: #{e.message}"
    end
  end

  private

  # AVM API Calls
  def call_avm_initiate_api(payload, secret_key)
    connection = Faraday.new(url: AVM_BASE_URL) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    connection.post("api/v1/documents?encryptionKey=#{secret_key}", payload)
  end

  def call_avm_status_api(document_id, if_modified_since, encryption_key)
    connection = Faraday.new(url: AVM_BASE_URL) do |faraday|
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 10
    end

    connection.get("api/v1/documents/#{document_id}?encryptionKey=#{encryption_key}") do |req|
      req.headers['If-Modified-Since'] = if_modified_since.to_s if if_modified_since
    end
  end

  def call_avm_download_api(document_id, encryption_key)
    connection = Faraday.new(url: AVM_BASE_URL) do |faraday|
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    connection.get("api/v1/documents/#{document_id}?encryptionKey=#{encryption_key}")
  end

  # Autogram API Calls
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
        level: document.content_type == "application/pdf" ? "PAdES_BASELINE_B" : "XAdES_BASELINE_B"
      },
      payloadMimeType: determine_payload_mime_type(document)
    }

    connection.post("/visualization", payload)
  end

  # AVM Response Parsers
  def parse_avm_initiate_response(response, secret_key)
    data = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)

    {
      document_id: data["guid"],
      encryption_key: secret_key,
      signing_started_at: DateTime.parse(response.headers['Last-Modified'])
    }
  rescue JSON::ParserError => e
    { error: "Nepodarilo sa spracovať odpoveď z AVM služby: #{e.message}" }
  end

  def parse_avm_status_response(response)
    if response.status == 304
      return { status: 'pending' }
    end

    if response.status == 200
      return { status: 'completed' }
    end

    {
      status: 'failed',
      error: response.body["error"]
    }
  rescue JSON::ParserError => e
    { status: 'failed', error: "Nepodarilo sa spracovať odpoveď z AVM služby: #{e.message}" }
  end

  def parse_avm_download_response(response_body)
    data = response_body.is_a?(Hash) ? response_body : JSON.parse(response_body)
    data["content"]

  rescue JSON::ParserError => e
    raise "Nepodarilo sa spracovať odpoveď z AVM služby: #{e.message}"
  end

  def format_signature_parameters_for_avm(signature_parameters)
    {
      level: "#{signature_parameters.format}_#{signature_parameters.level}",
      container: signature_parameters.container,
      autoLoadEform: true
    }
  end

  # Mock methods for development
  def mock_avm_initiate_result
    {
      document_id: "mock_doc_#{SecureRandom.hex(8)}",
      encryption_key: "mock_key_#{SecureRandom.hex(16)}"
    }
  end

  def mock_avm_status_result
    # Simulate a random status for testing
    statuses = ['pending', 'completed', 'failed']
    status = statuses.sample

    case status
    when 'completed'
      { status: 'completed' }
    when 'failed'
      { status: 'failed', error: 'Mock signing failed' }
    else
      { status: 'pending' }
    end
  end

  def mock_signed_document_content
    # Return mock base64 encoded content for a "signed" document
    mock_content = "Mock signed document content - #{Time.current}"
    Base64.strict_encode64(mock_content)
  end

  def parse_validation_response(response_body)
    # Faraday with JSON middleware returns parsed data directly
    data = response_body.is_a?(Hash) ? response_body : JSON.parse(response_body)

    # Extract data from the 'value' object
    signatures_data = data["signatures"]
    signed_objects = data["signedObjects"] || []
    unsigned_objects = data["unsignedObjects"] || []

    # Determine if there are signatures
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
    # Faraday with JSON middleware returns parsed data directly
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

    # Extract signer name from certificate subject DN
    subject_dn = signing_cert["subjectDN"] || ""
    signer_name = extract_cn_from_dn(subject_dn)

    # Get the first timestamp for signing time
    first_timestamp = timestamps.find { |ts| ts["timestampType"] == "SIGNATURE_TIMESTAMP" }
    signing_time = if signatures_data["claimedSigningTime"]
      Time.parse(signatures_data["claimedSigningTime"])
    elsif first_timestamp
      Time.parse(first_timestamp["productionTime"])
    else
      nil
    end

    # Check if timestamps are qualified
    has_qualified_timestamps = signatures_data["areQualifiedTimestamps"]

    {
      signer_name: signer_name,
      signing_time: signing_time,
      signature_level: signatures_data["level"],
      validation_result: signatures_data["validationResult"],
      valid: signatures_data["validationResult"] == "TOTAL_PASSED",
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
            authority: extract_cn_from_dn(ts["subjectDN"] || ""),
            qualification: ts["qualification"]
          }
        end
      } : nil
    }
  end

  def extract_cn_from_dn(dn)
    # Extract Common Name from Distinguished Name
    match = dn.match(/CN=([^,]+)/)
    match ? match[1].strip : dn
  end

  def mock_validation_result(document)
    # Return mock data based on filename to simulate different scenarios
    filename = document.filename.downcase

    if filename.include?("signed") || filename.include?("podpisany")
      # Mock a file with signatures
      ValidationResult.new(
        has_signatures: true,
        signatures: [
          {
            signer_name: "Ján Novák",
            signing_time: 2.days.ago,
            signature_level: "PAdES_BASELINE_B",
            validation_result: "TOTAL_PASSED",
            valid: true,
            certificate_info: {
              subject: "CN=Ján Novák, O=Example Corp, C=SK",
              issuer: "CN=Slovak Post CA, O=Slovenská pošta, C=SK",
              qualification: "QESIG"
            },
            timestamp_info: nil
          }
        ],
        document_info: {
          container_type: document.content_type == "application/pdf" ? nil : "ASiC_E",
          signature_form: document.content_type == "application/pdf" ? "PAdES" : "XAdES",
          signed_objects_count: 1,
          unsigned_objects_count: 0,
          signed_objects: [ { id: "mock-id", mimeType: document.content_type, filename: document.filename } ],
          unsigned_objects: []
        }
      )
    elsif filename.include?("timestamp") || filename.include?("peciatka")
      # Mock a file with timestamped signature
      ValidationResult.new(
        has_signatures: true,
        signatures: [
          {
            signer_name: "Mária Svobodová",
            signing_time: 1.day.ago,
            signature_level: "PAdES_BASELINE_T",
            validation_result: "TOTAL_PASSED",
            valid: true,
            certificate_info: {
              subject: "CN=Mária Svobodová, O=Government Office, C=SK",
              issuer: "CN=Slovak Government CA, O=Government, C=SK",
              qualification: "QESIG"
            },
            timestamp_info: {
              count: 1,
              qualified: true,
              timestamps: [
                {
                  type: "SIGNATURE_TIMESTAMP",
                  time: 1.day.ago,
                  authority: "TSA Authority SK",
                  qualification: "QTSA"
                }
              ]
            }
          }
        ],
        document_info: {
          container_type: nil,
          signature_form: "PAdES",
          signed_objects_count: 1,
          unsigned_objects_count: 0,
          signed_objects: [ { id: "mock-timestamp-id", mimeType: "application/pdf", filename: document.filename } ],
          unsigned_objects: []
        }
      )
    else
      # Mock a file without signatures
      ValidationResult.new(
        has_signatures: false,
        signatures: [],
        document_info: {
          container_type: document.content_type == "application/pdf" ? nil : "ASiC_E",
          signature_form: document.content_type == "application/pdf" ? "PAdES" : "XAdES",
          signed_objects_count: 0,
          unsigned_objects_count: 1,
          signed_objects: [],
          unsigned_objects: [ { mimeType: document.content_type, filename: document.filename } ]
        }
      )
    end
  end

  def mock_visualization_result(document)
    # Return mock visualization data
    mock_content = "Mock document content for: #{document.filename}"
    encoded_filename = Base64.strict_encode64(document.filename.to_s)

    {
      content: mock_content,
      mime_type: "text/plain",
      filename: encoded_filename
    }
  end

  def error_result(message)
    ValidationResult.new(
      has_signatures: false,
      errors: [ message ]
    )
  end
end
