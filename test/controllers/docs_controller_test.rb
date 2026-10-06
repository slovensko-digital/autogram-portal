require "test_helper"

class DocsControllerTest < ActionDispatch::IntegrationTest
  test "federation documentation is shown only when the federation base URL is configured" do
    with_federation_base_url(nil) do
      get docs_path
      assert_response :success
      assert_select "section#federation", count: 0
      assert_select "a[href='#federation']", count: 0
    end

    with_federation_base_url("https://portal.example.com") do
      get docs_path
      assert_response :success
      assert_select "section#federation", count: 1
      assert_select "a[href='#federation']", count: 1
    end
  end

  private

  def with_federation_base_url(value)
    original = ENV["FEDERATION_BASE_URL"]
    value.nil? ? ENV.delete("FEDERATION_BASE_URL") : ENV["FEDERATION_BASE_URL"] = value
    yield
  ensure
    original.nil? ? ENV.delete("FEDERATION_BASE_URL") : ENV["FEDERATION_BASE_URL"] = original
  end
end
