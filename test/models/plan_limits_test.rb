require "test_helper"
require_relative "../support/plan_limits_helper"

class PlanLimitsTest < ActiveSupport::TestCase
  include PlanLimitsHelper

  LIMIT_KEYS = %w[MAX_MEMBERS MAX_STORED_DOCUMENTS STORAGE_GB MONTHLY_SIGNATURE_REQUESTS MONTHLY_TIMESTAMPS RETENTION_DAYS].freeze

  test "limits are unlimited unless configured, except a single Basic member" do
    unset = LIMIT_KEYS.flat_map { |key| [ "BASIC_#{key}", "PRO_#{key}" ] }.index_with { nil }

    with_plan_limits(unset.merge("MAX_DOCUMENT_SIZE_MB" => nil)) do
      basic = PlanLimits.for(:basic)
      assert_equal 1, basic.max_members
      assert_nil basic.max_stored_documents
      assert_nil basic.storage_bytes
      assert_nil basic.monthly_signature_requests
      assert_nil basic.monthly_timestamps
      assert_nil basic.retention

      assert_equal PlanLimits::Limits.new(max_members: nil, max_stored_documents: nil, storage_bytes: nil, monthly_signature_requests: nil, monthly_timestamps: nil, retention: nil),
                   PlanLimits.for(:pro)
      assert_nil PlanLimits.max_document_bytes
      assert_empty PlanLimits.plans_with_retention
    end
  end

  test "reads the limits of each plan from ENV in their units" do
    with_plan_limits(
      "BASIC_MAX_STORED_DOCUMENTS" => "10",
      "BASIC_MONTHLY_SIGNATURE_REQUESTS" => "10",
      "BASIC_MONTHLY_TIMESTAMPS" => " 10 ",
      "BASIC_RETENTION_DAYS" => "60",
      "PRO_STORAGE_GB" => "50",
      "PRO_MAX_MEMBERS" => "",
      "MAX_DOCUMENT_SIZE_MB" => "25"
    ) do
      basic = PlanLimits.for("basic")
      assert_equal 10, basic.max_stored_documents
      assert_equal 10, basic.monthly_signature_requests
      assert_equal 10, basic.monthly_timestamps
      assert_equal 60.days, basic.retention

      pro = PlanLimits.for(:pro)
      assert_equal 50.gigabytes, pro.storage_bytes
      assert_nil pro.max_members
      assert_nil pro.retention

      assert_equal 25.megabytes, PlanLimits.max_document_bytes
      assert_equal [ "basic" ], PlanLimits.plans_with_retention
    end
  end

  test "a blank Basic member limit removes the default and invalid values are ignored" do
    with_plan_limits("BASIC_MAX_MEMBERS" => "", "BASIC_MONTHLY_TIMESTAMPS" => "ten") do
      assert_nil PlanLimits.for(:basic).max_members
      assert_nil PlanLimits.for(:basic).monthly_timestamps
    end
  end

  test "retention periods have defaults that keep anonymous documents under an hour" do
    with_plan_limits("ANONYMOUS_RETENTION_MINUTES" => nil, "PLAN_CHANGE_RETENTION_GRACE_DAYS" => nil, "SIGNED_HISTORY_DAYS" => nil) do
      assert_equal 55.minutes, PlanLimits.anonymous_retention
      assert_equal 30.days, PlanLimits.plan_change_grace
      assert_nil PlanLimits.signed_history
    end

    with_plan_limits("ANONYMOUS_RETENTION_MINUTES" => "10", "PLAN_CHANGE_RETENTION_GRACE_DAYS" => "7", "SIGNED_HISTORY_DAYS" => "60") do
      assert_equal 10.minutes, PlanLimits.anonymous_retention
      assert_equal 7.days, PlanLimits.plan_change_grace
      assert_equal 60.days, PlanLimits.signed_history
    end
  end
end
