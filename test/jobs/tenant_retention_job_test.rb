require "test_helper"
require_relative "../support/plan_limits_helper"

class TenantRetentionJobTest < ActiveJob::TestCase
  include PlanLimitsHelper

  setup do
    @basic = Tenant.create!(name: "Basic firma")
    @pro = Tenant.create!(name: "PRO firma", plan: :pro)
  end

  test "deletes documents and bundles older than the retention of the plan" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60", "PRO_RETENTION_DAYS" => nil) do
      expired = create_contract(@basic, created_at: 61.days.ago)
      kept = create_contract(@basic, created_at: 59.days.ago)
      expired_bundle = Bundle.create!(tenant: @basic, contracts: [ create_contract(@basic) ], created_at: 61.days.ago)
      @basic.usage_records.create!(contract: expired, kind: :signature_request, source: :notification)
      pro_contract = create_contract(@pro, created_at: 1.year.ago)

      TenantRetentionJob.perform_now

      assert_not Contract.exists?(expired.id)
      assert_not Bundle.exists?(expired_bundle.id)
      assert_empty @basic.contracts.where(bundle_id: expired_bundle.id)
      assert Contract.exists?(kept.id)
      assert Contract.exists?(pro_contract.id), "PRO keeps documents until the owner deletes them"
      assert_equal 1, @basic.usage_of(:signature_requests), "usage outlives the deleted documents"
    end
  end

  test "keeps the documents of a tenant whose plan changed during the grace period" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60", "PLAN_CHANGE_RETENTION_GRACE_DAYS" => "30") do
      @pro.update!(plan: :basic)
      from_pro = create_contract(@pro, created_at: 1.year.ago)

      TenantRetentionJob.perform_now
      assert Contract.exists?(from_pro.id)

      @pro.update_column(:plan_changed_at, 31.days.ago)
      TenantRetentionJob.perform_now
      assert_not Contract.exists?(from_pro.id)
    end
  end

  test "deletes nothing without a configured retention" do
    with_plan_limits("BASIC_RETENTION_DAYS" => nil, "PRO_RETENTION_DAYS" => nil) do
      contract = create_contract(@basic, created_at: 10.years.ago)

      TenantRetentionJob.perform_now

      assert Contract.exists?(contract.id)
    end
  end

  private

  def create_contract(tenant, created_at: Time.current)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 retention"), filename: "doc.pdf", content_type: "application/pdf")
    Contract.create!(tenant: tenant, documents: [ Document.new(blob: blob) ], created_at: created_at)
  end
end
