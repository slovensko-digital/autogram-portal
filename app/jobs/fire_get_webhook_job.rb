class FireGetWebhookJob < ApplicationJob
  def perform(url:, webhook_id:, provider: Faraday)
    attempt_timestamp = Time.now.to_i

    response = provider.get(url, {}, {
      "webhook-id" => webhook_id,
      "webhook-timestamp" => attempt_timestamp.to_s
    })
    raise unless response.status <= 204
  end
end
