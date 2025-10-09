json.id contract.uuid
json.allowed_methods contract.allowed_methods
json.signature_parameters do
  json.container contract.signature_parameters&.container
  json.format contract.signature_parameters&.format
  json.level contract.signature_parameters&.level
end
json.documents contract.documents, partial: "api/v1/documents/document", as: :document
json.signed_document contract.signed_document, partial: "api/v1/contracts/signed_document", as: :signed_document unless contract.awaiting_signature?
