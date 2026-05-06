class FireGetWebhookJob < ApplicationJob
  OPEN_TIMEOUT_SECONDS = ENV.fetch("WEBHOOK_OPEN_TIMEOUT", "3").to_i
  REQUEST_TIMEOUT_SECONDS = ENV.fetch("WEBHOOK_TIMEOUT", "5").to_i

  def perform(url:, webhook_id:, provider: Faraday)
    attempt_timestamp = Time.now.to_i

    response = provider.get(
      url,
      {},
      {
        "webhook-id" => webhook_id,
        "webhook-timestamp" => attempt_timestamp.to_s
      }
    ) do |request|
      request.options.open_timeout = OPEN_TIMEOUT_SECONDS
      request.options.timeout = REQUEST_TIMEOUT_SECONDS
    end

    raise unless response.status <= 204
  rescue Faraday::Error => e
    raise "Webhook delivery failed: #{e.message}"
  end
end
