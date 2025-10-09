class FireStandardWebhookJob < ApplicationJob
  def perform(url:, webhook_id:, payload:, method: :post, provider: Faraday)
    private_key = OpenSSL::PKey::EC.new(Base64.decode64(ENV.fetch("WEBHOOK_PRIVATE_KEY")))
    attempt_timestamp = Time.now.to_i

    hash = OpenSSL::Digest.digest("SHA256", "#{webhook_id}.#{attempt_timestamp}.#{payload.to_json}")
    signature = private_key.sign_raw("SHA256", hash)
    headers = {
      "webhook-id" => webhook_id,
      "webhook-timestamp" => attempt_timestamp.to_s,
      "webhook-signature" => "v1a,#{Base64.strict_encode64(signature)}",
      "Content-Type" => "application/json"
    }

    response = provider.post(url, payload.to_json, headers)
    raise "Unexpected response status: #{response.status}" unless response.status <= 204
  end
end
