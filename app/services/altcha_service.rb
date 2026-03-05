# frozen_string_literal: true

require "openssl"
require "securerandom"
require "base64"
require "json"

# Implements the ALTCHA proof-of-work challenge protocol.
# See https://altcha.org/docs/api/
class AltchaService
  ALGORITHM = "SHA-256"
  MAX_NUMBER = 100_000

  def self.create_challenge(hmac_key:, max_number: MAX_NUMBER)
    salt = SecureRandom.hex(12)
    secret_number = rand(0..max_number)
    challenge = OpenSSL::Digest::SHA256.hexdigest("#{salt}#{secret_number}")
    signature = OpenSSL::HMAC.hexdigest("SHA256", hmac_key, challenge)

    {
      algorithm: ALGORITHM,
      challenge: challenge,
      salt: salt,
      signature: signature,
      maxnumber: max_number
    }
  end

  def self.verify_solution(payload_base64, hmac_key:)
    payload = JSON.parse(Base64.decode64(payload_base64))

    return false unless payload["algorithm"] == ALGORITHM

    challenge = OpenSSL::Digest::SHA256.hexdigest("#{payload["salt"]}#{payload["number"]}")
    return false unless challenge == payload["challenge"]

    expected_signature = OpenSSL::HMAC.hexdigest("SHA256", hmac_key, challenge)
    ActiveSupport::SecurityUtils.secure_compare(expected_signature, payload["signature"].to_s)
  rescue JSON::ParserError, ArgumentError
    false
  end
end
