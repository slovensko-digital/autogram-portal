class AvmService
  AVM_BASE_URL = ENV.fetch("AVM_URL", "https://autogram.slovensko.digital")

  def initiate_signing(contract)
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
        parameters: format_signature_parameters_for_avm(contract.signature_parameters, document),
        payloadMimeType: document.content_type + ";base64"
      }

      puts "Payload for AVM initiate: #{payload.inspect}"

      secret_key = CGI.escape(Base64.strict_encode64(SecureRandom.random_bytes(32)))
      puts "Generated secret key: #{secret_key}"

      response = call_avm_initiate_api(payload, secret_key)
      Rails.logger.info "AVM initiate response status: #{response.status}, body: #{response.body}"

      if response.success?
        parse_avm_initiate_response(response, secret_key)
      else
        { error: "Chyba komunikácie s AVM službou: #{response.status}" }
      end
    rescue StandardError => e
      Rails.logger.error "Error initiating AVM signing: #{e.message}"
      return { error: "Chyba komunikácie s AVM službou" } if Rails.env.production?

      # Fallback to mock data if service is not available
      Rails.logger.warn "AVM service not available, using mock data: #{e.message}"
      mock_avm_initiate_result
    end
  end

  def check_signing_status(document_id, if_modified_since, encryption_key)
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

  def download_signed_document(document_id, encryption_key)
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

  def format_signature_parameters_for_avm(signature_parameters, document)
    {
      level: "#{signature_parameters.format}_#{signature_parameters.level}",
      container: signature_parameters.container,
      fsFormId: document.xdc_parameters&.fs_form_identifier,
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
end
