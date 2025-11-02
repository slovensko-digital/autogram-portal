class AvmService
  AVM_BASE_URL = ENV.fetch("AVM_URL", "https://autogram.slovensko.digital")

  def initiate_signing(contract)
    document = contract.documents.first
    return { error: "No document to sign" } unless document&.blob&.attached?

    file_content = Base64.strict_encode64(document.content)

    payload = {
      document: {
        content: file_content,
        filename: document.filename
      },
      parameters: {
        level: "#{contract.signature_parameters.format}_#{contract.signature_parameters.level}",
        container: contract.signature_parameters.container,
        fsFormId: document.xdc_parameters&.fs_form_identifier,
        autoLoadEform: true
      },
      payloadMimeType: document.content_type + ";base64"
    }

    secret_key = CGI.escape(Base64.strict_encode64(SecureRandom.random_bytes(32)))
    response = call_avm_initiate_api(payload, secret_key)

    if response.success?
      parse_avm_initiate_response(response, secret_key)
    else
      { error: "Error communicating with AVM service: #{response.status}" }
    end
  rescue StandardError => e
    { error: "Error communicating with AVM service: #{e.message}" }
  end

  def check_signing_status(document_id, if_modified_since, encryption_key)
    response = call_avm_status_api(document_id, if_modified_since, encryption_key)

    if response.status < 400
      parse_avm_status_response(response)
    else
      { status: "failed", error: "Error communicating with AVM service: #{response.status}" }
    end
  rescue StandardError => e
    { status: "failed", error: "Error communicating with AVM service: #{e.message}" }
  end

  def download_signed_document(document_id, encryption_key)
    response = call_avm_download_api(document_id, encryption_key)

    if response.success?
      parse_avm_download_response(response.body)
    else
      raise "Error downloading signed document: #{response.status}"
    end
  rescue StandardError => e
    raise "Error communicating with AVM service: #{e.message}"
  end

  private

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
      req.headers["If-Modified-Since"] = if_modified_since.to_s if if_modified_since
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

  def parse_avm_initiate_response(response, secret_key)
    data = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)

    {
      document_id: data["guid"],
      encryption_key: secret_key,
      signing_started_at: DateTime.parse(response.headers["Last-Modified"])
    }
  rescue JSON::ParserError => e
    { error: "Failed to parse AVM response: #{e.message}" }
  end

  def parse_avm_status_response(response)
    if response.status == 304
      return { status: "pending" }
    end

    if response.status == 200
      return { status: "completed" }
    end

    {
      status: "failed",
      error: response.body["error"]
    }
  rescue JSON::ParserError => e
    { status: "failed", error: "Failed to parse AVM response: #{e.message}" }
  end

  def parse_avm_download_response(response_body)
    data = response_body.is_a?(Hash) ? response_body : JSON.parse(response_body)
    data["content"]

  rescue JSON::ParserError => e
    raise "Failed to parse AVM response: #{e.message}"
  end
end
