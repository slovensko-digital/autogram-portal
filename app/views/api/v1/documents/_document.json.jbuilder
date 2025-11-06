json.id document.uuid
json.filename document.filename
json.content_type document.blob.content_type
json.download_url rails_blob_url(document.blob)
json.xdc_parameters do
  json.auto_load_eform document.xdc_parameters .auto_load_eform
  json.container_xmlns document.xdc_parameters .container_xmlns
  json.embed_used_schemas document.xdc_parameters .embed_used_schemas
  json.fs_form_identifier document.xdc_parameters .fs_form_identifier
  json.identifier document.xdc_parameters .identifier
  json.schema document.xdc_parameters .schema
  json.schema_identifier document.xdc_parameters .schema_identifier
  json.schema_mime_type document.xdc_parameters .schema_mime_type
  json.transformation document.xdc_parameters .transformation
  json.transformation_identifier document.xdc_parameters .transformation_identifier
  json.transformation_language document.xdc_parameters .transformation_language
  json.transformation_media_destination_type_description document.xdc_parameters .transformation_media_destination_type_description
  json.transformation_target_environment document.xdc_parameters .transformation_target_environment
end if document.xdc_parameters
