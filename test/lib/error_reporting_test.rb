require "test_helper"
require "rack/mock"

# Error reports carry technical data only (config/initializers/rollbar.rb).
class ErrorReportingTest < ActiveSupport::TestCase
  include Rollbar::RequestDataExtractor

  PRIVATE_VALUES = %w[zmluva-novak JVBERi0 jan.novak Novak tajny-token cookie-secret 203.0.113.7].freeze

  test "a report of a failed API request carries no documents, recipients, tokens, cookies or IP address" do
    body = {
      contracts: [ { documents: [ { filename: "zmluva-novak.pdf", content: "JVBERi0xLjQgdGFqbmU=" } ] } ],
      recipients: [ { email: "jan.novak@example.com", name: "Jan Novak" } ]
    }.to_json
    env = Rack::MockRequest.env_for(
      "/api/v1/bundles?recipient=tajny-token",
      method: "POST", input: body, "CONTENT_TYPE" => "application/json",
      "HTTP_COOKIE" => "_autogram_portal_session=cookie-secret",
      "HTTP_REFERER" => "https://agp.example/bundles/1?recipient=tajny-token",
      "HTTP_X_FORWARDED_FOR" => "203.0.113.7", "REMOTE_ADDR" => "203.0.113.7",
      "action_dispatch.request_id" => "req-123",
      "action_dispatch.parameter_filter" => Rails.application.config.filter_parameters,
      "action_dispatch.request.path_parameters" => { controller: "api/v1/bundles", action: "create" },
      "rack.session" => { "current_tenant_id" => 42 }
    )

    report = extract_request_data_from_rack(env)

    assert_empty PRIVATE_VALUES.select { report.to_json.include?(it) }
    assert_nil report[:user_ip]
    assert_equal "/api/v1/bundles", URI(report[:url]).path
    assert_equal "req-123", report[:request_id], "the request id finds the request in our own logs"
    assert_equal({ controller: "api/v1/bundles", action: "create" }, report[:params].symbolize_keys)
  end

  test "a report of a failed mail or job names it but carries no arguments" do
    extra = { job: "NotificationMailer", action: "signature_request", params: { recipient: Recipient.new(email: "jan.novak@example.com", name: "Jan Novak") }, arguments: [ "jan.novak@example.com" ] }
    item = Rollbar::Item.new(level: "error", exception: RuntimeError.new("boom"), extra: extra, configuration: Rollbar.configuration, scope: Rollbar::LazyStore.new({}), logger: Rails.logger, notifier: Rollbar.notifier)

    report = item.build.to_json

    assert_empty PRIVATE_VALUES.select { report.include?(it) }
    assert_includes report, "NotificationMailer"
    assert_includes report, "signature_request"
  end
end
