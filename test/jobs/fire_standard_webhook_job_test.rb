require "test_helper"

class FireStandardWebhookJobTest < ActiveJob::TestCase
  Provider = Struct.new(:status) do
    def post(*)
      Struct.new(:status).new(status)
    end
  end

  setup do
    @queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    @original_private_key = ENV["WEBHOOK_PRIVATE_KEY"]
    ENV["WEBHOOK_PRIVATE_KEY"] = Base64.strict_encode64(OpenSSL::PKey::EC.generate("prime256v1").to_pem)
  end

  teardown do
    ENV["WEBHOOK_PRIVATE_KEY"] = @original_private_key
    ActiveJob::Base.queue_adapter = @queue_adapter
  end

  test "retries delivery to an unreachable endpoint" do
    assert_enqueued_with(job: FireStandardWebhookJob, args: [ { url: "http://127.0.0.1:9/webhook", webhook_id: "id", payload: { type: "contract.signed" } } ]) do
      FireStandardWebhookJob.perform_now(url: "http://127.0.0.1:9/webhook", webhook_id: "id", payload: { type: "contract.signed" })
    end
  end

  test "does not retry delivered webhook" do
    assert_no_enqueued_jobs do
      FireStandardWebhookJob.perform_now(url: "https://example.com/webhook", webhook_id: "id", payload: { type: "contract.signed" }, provider: Provider.new(204))
    end
  end
end
