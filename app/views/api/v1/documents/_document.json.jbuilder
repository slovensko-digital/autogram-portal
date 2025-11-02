json.id document.uuid
json.filename document.filename
json.content_type document.blob.content_type
json.download_url rails_blob_url(document.blob)
json.xdc_parameters document.xdc_parameters do |xdc|
  json.auto_load_eform xdc.auto_load_eform
  json.container_xmlns xdc.container_xmlns
  json.embed_used_schemas xdc.embed_used_schemas
  json.fs_form_identifier xdc.fs_form_identifier
  json.identifier xdc.identifier
  json.schema xdc.schema
  json.schema_identifier xdc.schema_identifier
  json.schema_mime_type xdc.schema_mime_type
  json.transformation xdc.transformation
  json.transformation_identifier xdc.transformation_identifier
  json.transformation_language xdc.transformation_language
  json.transformation_media_destination_type_description xdc.transformation_media_destination_type_description
  json.transformation_target_environment xdc.transformation_target_environment
end if document.xdc_parameters
