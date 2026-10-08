// Signature parameters of POST /api/v1/sign (Autogram >= 2.8.0), which names the portal's
// format and level form and profile and ignores keys it does not know.
export function versionedSignatureParameters(signatureParameters) {
  return {
    form: signatureParameters.format,
    profile: signatureParameters.level,
    container: signatureParameters.container,
    en319132: signatureParameters.en319132
  }
}
