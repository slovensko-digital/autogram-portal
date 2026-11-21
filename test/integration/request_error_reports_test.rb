require "test_helper"

# What errors in requests send to Rollbar (config/initializers/rollbar.rb).
class RequestErrorReportsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  class FailingController < ActionController::Base
    def show = raise("boom")
  end

  test "an error in a request is reported without identifying the signed-in user" do
    users(:one).update_column(:confirmed_at, Time.current)
    sign_in users(:one)

    reports = capture_reports do
      with_routing do |routes|
        routes.draw { get "/failing", to: "request_error_reports_test/failing#show" }
        assert_raises(RuntimeError) { get "/failing" }
      end
    end

    report = reports.sole
    assert_equal "boom", report.dig("data", :body, :trace, :exception, :message)
    assert_nil report.dig("data", :person)
  end

  private

  # Rollbar is disabled in tests; this turns it on and keeps the reports instead of sending them. Rollbar
  # sends its own internal errors directly, to an endpoint that is not listening here.
  def capture_reports(&)
    reports = []
    Rollbar.with_config(enabled: true, access_token: "test", endpoint: "http://127.0.0.1:9/", use_async: true, async_handler: ->(payload) { reports << payload }, &)
    reports
  end
end
