# The phone link of a paper signature (the QR code on the paper signing page): it opens that one paper
# signature without signing in, so the signer can photograph the signed pages on a phone. It carries only
# the paper signature and an expiry; PaperSignerResolution accepts it only while the paper signature is a
# draft of the contract in the URL and only for its pages and submitting.
class PaperSignatureAccessToken
  PURPOSE = "paper-signature-access".freeze
  DEFAULT_TTL = 1.hour

  class << self
    def generate(paper_signature, expires_at: DEFAULT_TTL.from_now)
      verifier.generate(
        {
          paper_signature_uuid: paper_signature.uuid,
          exp: expires_at.to_i
        }
      )
    end

    # The paper signature of a valid token, nil for an expired, tampered or foreign one.
    def verify(token)
      return unless token.is_a?(String)

      payload = verifier.verified(token)
      return unless payload.is_a?(Hash)

      payload = payload.with_indifferent_access
      return unless payload[:exp].to_i >= Time.current.to_i

      PaperSignature.find_by(uuid: payload[:paper_signature_uuid].to_s)
    end

    private

    def verifier
      Rails.application.message_verifier(PURPOSE)
    end
  end
end
