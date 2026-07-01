signer_contract = @session.signer_contract
recipient = signer_contract.recipient
prepared_signature_field = @contract.prepared_signature_field_preparation_for(recipient: recipient)
prepared_signature_field_appearance = if prepared_signature_field.present?
  signer_contract.latest_signature_field_appearance_for(prepared_signature_field.document)
end
documents = @contract.documents_to_sign_for(signer_contract: signer_contract)

json.id @contract.uuid
json.signature_parameters do
  json.container @contract.signature_parameters&.container
  json.format @contract.signature_parameters&.format
  json.level @contract.signature_parameters&.level
  json.en319132 @contract.signature_parameters&.en319132
  json.add_content_timestamp @contract.signature_parameters&.add_content_timestamp
end
json.documents documents do |document|
  json.id document.uuid
  json.filename document.filename
  json.content_type document.blob.content_type
  json.download_url rails_blob_url(document.blob)

  if document.xdc_parameters
    json.xdc_parameters do
      json.auto_load_eform document.xdc_parameters.auto_load_eform
      json.container_xmlns document.xdc_parameters.container_xmlns
      json.embed_used_schemas document.xdc_parameters.embed_used_schemas
      json.fs_form_identifier document.xdc_parameters.fs_form_identifier
      json.identifier document.xdc_parameters.identifier
      json.schema document.xdc_parameters.schema
      json.schema_identifier document.xdc_parameters.schema_identifier
      json.schema_mime_type document.xdc_parameters.schema_mime_type
      json.transformation document.xdc_parameters.transformation
      json.transformation_identifier document.xdc_parameters.transformation_identifier
      json.transformation_language document.xdc_parameters.transformation_language
      json.transformation_media_destination_type_description document.xdc_parameters.transformation_media_destination_type_description
      json.transformation_target_environment document.xdc_parameters.transformation_target_environment
    end
  end

  next unless documents.one? && prepared_signature_field.present? && prepared_signature_field_appearance.present?

  json.visible_signature do
    json.field_id prepared_signature_field.field_identifier

    if prepared_signature_field_appearance.image.attached?
      json.image do
        json.filename prepared_signature_field_appearance.image.filename.to_s
        json.content Base64.strict_encode64(prepared_signature_field_appearance.image.download)
        json.mime_type "#{prepared_signature_field_appearance.image.blob.content_type};base64"
      end
    else
      json.text VisualStamp.pades_visible_signature_text(prepared_signature_field_appearance.custom_text)
    end
  end
end
json.multiple_documents documents.many?
