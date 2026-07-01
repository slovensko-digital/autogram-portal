class AvmService
  AVM_BASE_URL = ENV.fetch("AVM_URL", "https://autogram.slovensko.digital")

  def initiate_signing(contract, signer_contract: nil)
    documents = contract.documents_to_sign_for(signer_contract: signer_contract)
    document = documents.first
    return { error: "No document to sign" } unless document&.blob&.attached?

    file_content = Base64.strict_encode64(document.content)

    parameters = {
      level: "#{contract.signature_parameters.format}_#{contract.signature_parameters.level}",
      container: contract.signature_parameters.container,
      fsFormId: document.xdc_parameters&.fs_form_identifier,
      autoLoadEform: true
    }

    visible_signature = avm_visible_signature(contract, signer_contract: signer_contract, documents: documents)
    parameters[:visibleSignature] = visible_signature if visible_signature

    payload = {
      document: {
        content: file_content,
        filename: document.filename
      },
      parameters: parameters,
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

  def check_signing_status(document_identifier, if_modified_since, encryption_key)
    response = call_avm_status_api(document_identifier, if_modified_since, encryption_key)

    if response.status < 400
      parse_avm_status_response(response)
    else
      { status: "failed", error: "Error communicating with AVM service: #{response.status}" }
    end
  rescue StandardError => e
    { status: "failed", error: "Error communicating with AVM service: #{e.message}" }
  end

  def download_signed_document(document_identifier, encryption_key)
    response = call_avm_download_api(document_identifier, encryption_key)

    if response.success?
      parse_avm_download_response(response.body)
    else
      raise "Error downloading signed document: #{response.status}"
    end
  rescue StandardError => e
    raise "Error communicating with AVM service: #{e.message}"
  end

  private

  def avm_visible_signature(contract, signer_contract:, documents:)
    return unless signer_contract && documents.one?

    recipient = signer_contract.recipient
    prepared_signature_field = contract.prepared_signature_field_preparation_for(recipient: recipient)
    return unless prepared_signature_field.present?

    appearance = signer_contract.latest_signature_field_appearance_for(prepared_signature_field.document)
    return unless appearance.present?

    visible_signature = {
      fieldId: prepared_signature_field.field_identifier
    }

    if appearance.image.attached?
      visible_signature[:image] = {
        filename: appearance.image.filename.to_s,
        content: Base64.strict_encode64(appearance.image.download),
        mimeType: "#{appearance.image.blob.content_type};base64"
      }
    else
      visible_signature[:text] = VisualStamp.pades_visible_signature_text(appearance.custom_text)
    end

    visible_signature
  end

  def call_avm_initiate_api(payload, secret_key)
    connection = Faraday.new(url: AVM_BASE_URL) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    connection.post("api/v1/documents?encryptionKey=#{secret_key}", payload)
  end

  def call_avm_status_api(document_identifier, if_modified_since, encryption_key)
    connection = Faraday.new(url: AVM_BASE_URL) do |faraday|
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 10
    end

    connection.get("api/v1/documents/#{document_identifier}?encryptionKey=#{encryption_key}") do |req|
      req.headers["If-Modified-Since"] = if_modified_since.to_s if if_modified_since
    end
  end

  def call_avm_download_api(document_identifier, encryption_key)
    connection = Faraday.new(url: AVM_BASE_URL) do |faraday|
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    connection.get("api/v1/documents/#{document_identifier}?encryptionKey=#{encryption_key}")
  end

  def parse_avm_initiate_response(response, secret_key)
    data = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body)

    {
      document_identifier: data["guid"],
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
