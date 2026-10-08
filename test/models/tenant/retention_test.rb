require "test_helper"
require_relative "../../support/plan_limits_helper"

class Tenant::RetentionTest < ActiveSupport::TestCase
  include PlanLimitsHelper

  setup do
    @tenant = Tenant.create!(name: "Basic firma")
  end

  test "documents are due for deletion after the retention of the plan" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60") do
      created_at = 10.days.ago

      assert_equal created_at + 60.days, @tenant.retention_deletion_at(created_at)
    end
  end

  test "plans without retention keep documents" do
    with_plan_limits("BASIC_RETENTION_DAYS" => nil) do
      assert_nil @tenant.retention_deletion_at(1.year.ago)
      assert_nil @tenant.retention_cutoff
    end
  end

  test "the grace period after a plan change postpones the deletion" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60", "PLAN_CHANGE_RETENTION_GRACE_DAYS" => "30") do
      @tenant.update_column(:plan_changed_at, 5.days.ago)

      assert_equal 25.days.from_now.to_date, @tenant.retention_deletion_at(1.year.ago).to_date
      assert_equal 70.days.from_now.to_date, @tenant.retention_deletion_at(10.days.from_now).to_date
      assert_nil @tenant.retention_cutoff
      assert_equal 26.days.from_now.to_date - 60, @tenant.retention_cutoff(at: 26.days.from_now).to_date
    end
  end

  test "the job deletes exactly the documents whose deletion date has passed" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60") do
      due = create_contract(created_at: 60.days.ago - 1.minute)
      not_due = create_contract(created_at: 60.days.ago + 1.minute)

      assert_operator due.scheduled_deletion_at, :<, Time.current
      assert_operator not_due.scheduled_deletion_at, :>, Time.current

      TenantRetentionJob.perform_now

      assert_not Contract.exists?(due.id)
      assert Contract.exists?(not_due.id)
    end
  end

  test "bundled documents are deleted together with their bundle" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60") do
      contract = create_contract(created_at: 1.day.ago)
      bundle = Bundle.create!(tenant: @tenant, contracts: [ contract ], created_at: 50.days.ago)

      assert_equal bundle.created_at + 60.days, contract.reload.scheduled_deletion_at
      assert_equal bundle.scheduled_deletion_at, contract.scheduled_deletion_at
    end
  end

  private

  def create_contract(created_at:)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 retention"), filename: "doc.pdf", content_type: "application/pdf")
    Contract.create!(tenant: @tenant, documents: [ Document.new(blob: blob) ], created_at: created_at)
  end
end
