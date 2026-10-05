require "test_helper"
require_relative "../support/plan_limits_helper"

class AboutControllerTest < ActionDispatch::IntegrationTest
  include PlanLimitsHelper

  test "the price list shows the Basic limits configured for the instance" do
    with_plan_limits("BASIC_MAX_STORED_DOCUMENTS" => "10", "BASIC_MONTHLY_SIGNATURE_REQUESTS" => "10", "BASIC_MONTHLY_TIMESTAMPS" => "5", "BASIC_RETENTION_DAYS" => "60", "BASIC_MAX_MEMBERS" => nil) do
      get about_index_path

      assert_response :success
      assert_includes response.body, I18n.t("about.index.start_using.basic.limits.stored_documents", count: 10)
      assert_includes response.body, I18n.t("about.index.start_using.basic.limits.signature_requests", count: 10)
      assert_includes response.body, I18n.t("about.index.start_using.basic.limits.timestamps", count: 5)
      assert_includes response.body, I18n.t("about.index.start_using.basic.limits.members", count: 1)
      assert_includes response.body, I18n.t("about.index.faq.storage_basic_retention", count: 60)
    end
  end

  test "the price list omits limits the instance does not have" do
    with_plan_limits("BASIC_MAX_STORED_DOCUMENTS" => nil, "BASIC_MONTHLY_SIGNATURE_REQUESTS" => nil, "BASIC_MONTHLY_TIMESTAMPS" => nil, "BASIC_RETENTION_DAYS" => nil, "BASIC_MAX_MEMBERS" => "") do
      get about_index_path

      assert_response :success
      I18n.t("about.index.start_using.basic.included").each { |item| assert_includes response.body, item }
      assert_not_includes response.body, I18n.t("about.index.start_using.basic.limits.members", count: 1)
      assert_not_includes response.body, I18n.t("about.index.faq.storage_basic_retention", count: 60)
    end
  end

  test "the price list links the full pricing page when PRICING_URL is set" do
    original = ENV["PRICING_URL"]
    ENV["PRICING_URL"] = "https://example.com/cennik"
    get about_index_path

    assert_response :success
    assert_select "a[href=?]", "https://example.com/cennik", text: /#{I18n.t("about.index.start_using.full_pricing")}/

    ENV["PRICING_URL"] = ""
    get about_index_path

    assert_select "a[href=?]", "https://example.com/cennik", count: 0
  ensure
    ENV["PRICING_URL"] = original
  end
end
