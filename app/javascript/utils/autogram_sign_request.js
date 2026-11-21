// Turns the Autogram parameters of a signing session (contracts/sessions/_autogram.json.jbuilder)
// into the arguments of DesktopClient#sign(documents, parameters, options) of autogram-sdk >= 0.7.
// One call signs one document or several documents into one ASiC-E container; the SDK picks the
// endpoint of the installed Autogram and refuses several documents for Autogram older than 2.8.0.

export function signatureParameters(parameters) {
  return withoutBlanks({
    form: parameters.format,
    profile: parameters.level,
    container: parameters.container
  })
}

// content is the document's content in base64
export function documentToSign(document, content) {
  return withoutBlanks({
    content: content,
    encoding: "base64",
    mimeType: document.content_type.split(";")[0].trim(),
    filename: document.filename,
    xdcParameters: xdcParameters(document.xdc_parameters)
  })
}

// Autogram before 2.8.0 reads the schema and the transformation in the encoding of the document,
// which is always base64 here, so plain text ones are sent in base64 too.
function xdcParameters(parameters) {
  if (!parameters) {
    return { autoLoadEform: true }
  }

  const result = {
    autoLoadEform: parameters.auto_load_eform,
    containerXmlns: parameters.container_xmlns,
    embedUsedSchemas: parameters.embed_used_schemas,
    fsFormIdentifier: parameters.fs_form_identifier,
    identifier: parameters.identifier,
    schemaIdentifier: parameters.schema_identifier,
    transformationIdentifier: parameters.transformation_identifier,
    transformationLanguage: parameters.transformation_language,
    transformationMediaDestinationTypeDescription: parameters.transformation_media_destination_type_description,
    transformationTargetEnvironment: parameters.transformation_target_environment
  }

  if (parameters.schema != null || parameters.transformation != null) {
    const schemaMimeType = parameters.schema_mime_type || "application/xml"
    const inBase64 = schemaMimeType.includes("base64")

    result.schema = inBase64 ? parameters.schema : textToBase64(parameters.schema)
    result.transformation = inBase64 ? parameters.transformation : textToBase64(parameters.transformation)
    result.schemaMimeType = inBase64 ? schemaMimeType : `${schemaMimeType};base64`
  }

  return withoutBlanks(result)
}

function textToBase64(text) {
  if (text == null) {
    return null
  }

  let binary = ""
  new TextEncoder().encode(text).forEach((byte) => { binary += String.fromCharCode(byte) })
  return btoa(binary)
}

// Autogram rejects null for its optional boolean parameters, leave out the ones the document does not set
function withoutBlanks(object) {
  return Object.fromEntries(Object.entries(object).filter(([, value]) => value != null))
}
