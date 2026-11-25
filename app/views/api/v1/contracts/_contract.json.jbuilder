json.id contract.uuid
json.allowed_methods contract.allowed_methods
json.signature_parameters do
  json.container contract.signature_parameters&.container
  json.format contract.signature_parameters&.format
  json.level contract.signature_parameters&.level
  json.en319132 contract.signature_parameters&.en319132
  json.add_content_timestamp contract.signature_parameters&.add_content_timestamp
end
json.documents contract.documents, partial: "api/v1/documents/document", as: :document
unless contract.awaiting_signature?
  # null for a contract signed only on paper: its scans are under paper_signatures
  if contract.signed_document_attached?
    json.signed_document contract.signed_document, partial: "api/v1/contracts/signed_document", as: :signed_document
  else
    json.signed_document nil
  end
end
paper_signatures = contract.paper_signatures.where(status: %w[submitted approved]).includes(signer_contract: { signer: :recipient }).order(:submitted_at, :id)
json.paper_signatures paper_signatures, partial: "api/v1/contracts/paper_signature", as: :paper_signature, contract: contract
