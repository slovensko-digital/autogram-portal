class EidentitaService
  def initiate_signing(contract)
    document = contract.documents_to_sign.first
    return { error: "No document to sign" } unless document&.blob&.attached?

    {
      signing_started_at: Time.current
    }
  rescue StandardError => e
    { error: "Error initiating Eidentita signing: #{e.message}" }
  end

  def build_json_payload(contract, eidentita_session)
    url_options = Rails.application.config.action_controller.default_url_options || {}

    source_url = Rails.application.routes.url_helpers.document_contract_eidentita_session_url(contract, eidentita_session, **url_options)

    callback_url = Rails.application.routes.url_helpers.contract_url(contract, **url_options)

    destination_url = Rails.application.routes.url_helpers.upload_contract_eidentita_session_url(contract, eidentita_session, **url_options)

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
