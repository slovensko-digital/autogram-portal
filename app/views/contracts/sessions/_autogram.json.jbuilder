json.id @contract.uuid
json.signature_parameters do
  json.container @contract.signature_parameters&.container
  json.format @contract.signature_parameters&.format
  json.level @contract.signature_parameters&.level
  json.en319132 @contract.signature_parameters&.en319132
  json.add_content_timestamp @contract.signature_parameters&.add_content_timestamp
end
json.documents @contract.documents_to_sign, partial: "api/v1/documents/document", as: :document
