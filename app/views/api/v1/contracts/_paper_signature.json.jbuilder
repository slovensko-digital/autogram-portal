json.recipient paper_signature.recipient&.uuid
json.status paper_signature.status
json.submitted_at paper_signature.submitted_at
json.approved_at paper_signature.approved? ? paper_signature.reviewed_at : nil
json.scan scan_api_v1_contract_paper_signature_url(contract, paper_signature)
