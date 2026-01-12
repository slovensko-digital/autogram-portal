class EidentitaService
  def initiate_signing(contract)
    document = contract.documents.first
    return { error: "No document to sign" } unless document&.blob&.attached?

    {
      signing_started_at: Time.current
    }
  rescue StandardError => e
    { error: "Error initiating Eidentita signing: #{e.message}" }
  end

  def build_json_payload(contract, eidentita_session)
    source_url = Rails.application.routes.url_helpers.document_contract_eidentita_session_url(
      contract,
      eidentita_session,
      host: ENV.fetch("APP_HOST", "localhost:3000"),
      protocol: ENV.fetch("APP_PROTOCOL", "http")
    )

    callback_url = Rails.application.routes.url_helpers.contract_url(
      contract,
      host: ENV.fetch("APP_HOST", "localhost:3000"),
      protocol: ENV.fetch("APP_PROTOCOL", "http")
    )

    destination_url = Rails.application.routes.url_helpers.upload_contract_eidentita_session_url(
      contract,
      eidentita_session,
      host: ENV.fetch("APP_HOST", "localhost:3000"),
      protocol: ENV.fetch("APP_PROTOCOL", "http")
    )

    signature_format = case contract.signature_parameters&.format
    when "XAdES"
      "asice-xades"
    when "PAdES"
      "pades"
    else
      "asice-xades"
    end

    signature_type = case true
    when contract.allowed_methods.include?("qes")
      "handwritten"
    when contract.allowed_methods.include?("ts-qes")
      "certified"
    else
      "handwritten"
    end

    {
      sourceUrl: source_url,
      signatureFormat: signature_format,
      signatureType: signature_type,
      callbackUrl: callback_url,
      destinationUrl: destination_url
    }
  end
end
