class AvmService
  DEFAULT_INTERACTIVE_BASE_URL = "https://autogram.slovensko.digital".freeze
  DEFAULT_DETACHED_SIGNING_BASE_URL = "http://localhost:7200".freeze

  class Error < StandardError; end

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

  def request_data_to_sign(contract, signer_contract: nil, signing_certificate:, signature_reference: nil, signature_instance: nil)
    request_data_to_sign_from_request(
      sign_request_body: build_sign_request_payload(
        contract,
        signer_contract: signer_contract,
        signature_reference: signature_reference,
        signature_instance: signature_instance
      ),
      signing_certificate: signing_certificate
    )
  end

  def build_signed_document(contract, signer_contract: nil, data_to_sign_structure:, signed_data:, signature_reference: nil, signature_instance: nil)
    build_signed_document_from_request(
      sign_request_body: build_sign_request_payload(
        contract,
        signer_contract: signer_contract,
        signature_reference: signature_reference,
        signature_instance: signature_instance
      ),
      data_to_sign_structure: data_to_sign_structure,
      signed_data: signed_data
    )
  end

  def request_data_to_sign_from_request(sign_request_body:, signing_certificate:)
    payload = {
      originalSignRequestBody: sign_request_body,
      signingCertificate: signing_certificate
    }

    response = call_avm_data_to_sign_api(payload)
    raise Error, "Error communicating with AVM service: #{response.status}" unless response.success?

    parse_avm_data_to_sign_response(response.body)
  rescue StandardError => e
    raise e if e.is_a?(Error)

    raise Error, "Error communicating with AVM service: #{e.message}"
  end

  def build_signed_document_from_request(sign_request_body:, data_to_sign_structure:, signed_data:)
    payload = {
      originalSignRequestBody: sign_request_body,
      dataToSignStructure: {
        dataToSign: data_to_sign_structure.fetch(:data_to_sign),
        signingTime: data_to_sign_structure.fetch(:signing_time),
        signingCertificate: data_to_sign_structure.fetch(:signing_certificate)
      },
      signedData: signed_data
    }

    response = call_avm_build_signature_api(payload)
    raise Error, "Error communicating with AVM service: #{response.status}" unless response.success?

    parse_avm_build_signature_response(response.body)
  rescue StandardError => e
    raise e if e.is_a?(Error)

    raise Error, "Error communicating with AVM service: #{e.message}"
  end

  def build_detached_sign_request_payload(filename:, content:, content_type:, level:, container: nil, packaging: nil, signature_reference: nil, signature_instance: nil)
    parameters = {
      level: level,
      container: container,
      packaging: packaging
    }
    parameters[:signatureReference] = signature_reference if signature_reference.present?
    parameters[:signatureInstance] = signature_instance if signature_instance.present?

    {
      document: {
        content: Base64.strict_encode64(content),
        filename: filename
      },
      parameters: parameters.compact,
      payloadMimeType: "#{content_type};base64"
    }
  end

  private

  def build_sign_request_payload(contract, signer_contract: nil, signature_reference: nil, signature_instance: nil)
    documents = contract.documents_to_sign_for(signer_contract: signer_contract)
    document = documents.first
    raise Error, "No document to sign" unless document&.blob&.attached?

    file_content = Base64.strict_encode64(document.content)

    parameters = {
      level: "#{contract.signature_parameters.format}_#{contract.signature_parameters.level}",
      container: contract.signature_parameters.container,
      fsFormId: document.xdc_parameters&.fs_form_identifier,
      autoLoadEform: true
    }
    if contract.signature_parameters.format == "XAdES" && contract.signature_parameters.container.present?
      parameters[:packaging] = "DETACHED"
    end
    parameters[:signatureReference] = signature_reference if signature_reference.present?
    parameters[:signatureInstance] = signature_instance if signature_instance.present?

    visible_signature = avm_visible_signature(contract, signer_contract: signer_contract, documents: documents)
    parameters[:visibleSignature] = visible_signature if visible_signature

    {
      document: {
        content: file_content,
        filename: document.filename
      },
      parameters: parameters,
      payloadMimeType: document.content_type + ";base64"
    }
  end

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
    connection = Faraday.new(url: interactive_base_url) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    connection.post("api/v1/documents?encryptionKey=#{secret_key}", payload)
  end

  def call_avm_data_to_sign_api(payload)
    connection = Faraday.new(url: detached_signing_base_url) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    connection.post("/datatosign", payload)
  end

  def call_avm_build_signature_api(payload)
    connection = Faraday.new(url: detached_signing_base_url) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
    end

    connection.post("/build-signature", payload)
  end

  def call_avm_status_api(document_identifier, if_modified_since, encryption_key)
    connection = Faraday.new(url: interactive_base_url) do |faraday|
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 10
    end

    connection.get("api/v1/documents/#{document_identifier}?encryptionKey=#{encryption_key}") do |req|
      req.headers["If-Modified-Since"] = if_modified_since.to_s if if_modified_since
    end
  end

  def call_avm_download_api(document_identifier, encryption_key)
    connection = Faraday.new(url: interactive_base_url) do |faraday|
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

  def parse_avm_data_to_sign_response(response_body)
    data = response_body.is_a?(Hash) ? response_body : JSON.parse(response_body)

    {
      data_to_sign: data.fetch("dataToSign"),
      signing_time: data.fetch("signingTime"),
      signing_certificate: data.fetch("signingCertificate")
    }
  rescue KeyError, JSON::ParserError => e
    raise Error, "Failed to parse AVM response: #{e.message}"
  end

  def parse_avm_build_signature_response(response_body)
    data = response_body.is_a?(Hash) ? response_body : JSON.parse(response_body)
    data.fetch("content")
  rescue KeyError, JSON::ParserError => e
    raise Error, "Failed to parse AVM response: #{e.message}"
  end

  def interactive_base_url
    ENV["AVM_URL"].presence || DEFAULT_INTERACTIVE_BASE_URL
  end

  def detached_signing_base_url
    ENV["AVM_DETACHED_URL"].presence || ENV["AUTOGRAM_SERVICE_URL"].presence || DEFAULT_DETACHED_SIGNING_BASE_URL
  end
end
