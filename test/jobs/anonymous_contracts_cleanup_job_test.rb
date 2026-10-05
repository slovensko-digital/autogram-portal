require "test_helper"
require_relative "../support/plan_limits_helper"

class AnonymousContractsCleanupJobTest < ActiveJob::TestCase
  include PlanLimitsHelper

  test "deletes anonymous documents older than the anonymous retention" do
    with_plan_limits("ANONYMOUS_RETENTION_MINUTES" => "30") do
      expired = create_contract(created_at: 31.minutes.ago)
      fresh = create_contract(created_at: 29.minutes.ago)
      owned = create_contract(created_at: 1.day.ago, tenant: Tenant.create!(name: "Firma"))

      AnonymousContractsCleanupJob.perform_now

      assert_not Contract.exists?(expired.id)
      assert Contract.exists?(fresh.id)
      assert Contract.exists?(owned.id)
    end
  end

  private

  def create_contract(created_at:, tenant: nil)
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4 anonymous"), filename: "doc.pdf", content_type: "application/pdf")
    Contract.create!(tenant: tenant, documents: [ Document.new(blob: blob) ], created_at: created_at)
  end
end
