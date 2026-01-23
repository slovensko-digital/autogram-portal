json.sourceUrl download_contract_session_url(@contract, @session)
json.callbackUrl contract_url(@contract)
json.destinationUrl upload_contract_session_url(@contract, @session)

json.signatureFormat case @contract.signature_parameters&.format
    when "XAdES"
      "asice-xades"
    when "PAdES"
      "pades"
    else
      "asice-xades"
    end

    json.signatureType case true
    when @contract.allowed_methods.include?("qes")
      "handwritten"
    when @contract.allowed_methods.include?("ts-qes")
      "certified"
    else
      "handwritten"
    end
