json.sourceUrl download_contract_session_url(@contract, @session)
json.callbackUrl contract_url(@contract)
json.destinationUrl upload_contract_session_url(@contract, @session)

json.signatureFormat case @contract.signature_parameters.format
when "XAdES"
  "asice-xades"
when "PAdES"
  "pades"
else
  "asice-xades"
end

json.signatureType case @contract.signature_parameters.level
when "BASELINE_B"
  "handwritten"
when "BASELINE_T", "BASELINE_LT", "BASELINE_LTA"
  "certified"
else
  "handwritten"
end
