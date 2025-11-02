json.hasSignatures @validation_result.has_signatures
json.signatures @validation_result.signatures.flatten.map do |signature|
  json.signerName signature[:signer_name]
  json.signingTime signature[:signing_time]&.iso8601
  json.signatureLevel signature[:signature_level]
  json.validationResult signature[:validation_result]
  json.valid signature[:valid]
  json.certificateInfo do
    json.subject signature.dig(:certificate_info, :subject)
    json.issuer signature.dig(:certificate_info, :issuer)
    json.qualification signature.dig(:certificate_info, :qualification)
  end
  json.timestampInfo do
    json.count signature.dig(:timestamp_info, :count)
    json.qualified signature.dig(:timestamp_info, :qualified)
    json.timestamps signature.dig(:timestamp_info, :timestamps)&.map do |ts|
      json.type ts[:type]
      json.time ts[:time]&.iso8601
      json.subject ts[:subject]
      json.qualification ts[:qualification]
    end
  end if signature[:timestamp_info].present?
end
json.documentInfo @validation_result.document_info
json.errors @validation_result.errors
