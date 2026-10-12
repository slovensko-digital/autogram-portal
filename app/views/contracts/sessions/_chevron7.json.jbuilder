session_token = SessionAccessToken.generate(contract: @contract, session: @session)
document = @contract.documents_to_sign_for(signer_contract: @session.signer_contract).first

json.version 1
json.portal "Autogram Portal"
json.sender @contract.bundle&.sender_display_name
json.document do
  json.filename document.filename
  json.contentType document.content_type
  json.sourceUrl download_contract_session_url(@contract, @session, session_token: session_token)
end
json.destinationUrl upload_contract_session_url(@contract, @session, session_token: session_token)
json.callbackUrl contract_url(@contract)
json.signatureParameters do
  json.format @contract.signature_parameters&.format
  json.level @contract.signature_parameters&.level
  json.container @contract.signature_parameters&.container
end
