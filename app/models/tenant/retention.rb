# When the retention of the tenant's plan (PlanLimits, e.g. BASIC_RETENTION_DAYS) deletes its bundles and
# standalone documents. TenantRetentionJob deletes what #retention_cutoff selects and the pages show the
# dates of #retention_deletion_at, so both follow the same rules, including the grace period after a plan
# change (PLAN_CHANGE_RETENTION_GRACE_DAYS).
module Tenant::Retention
  extend ActiveSupport::Concern

  # Documents due for deletion within this time are pointed out to the tenant.
  EXPIRING_SOON = 7.days

  # Bundles and standalone contracts created before the returned time are deleted at +at+. Nil when the plan
  # keeps documents or the grace period after a plan change still runs at +at+.
  def retention_cutoff(at: Time.current)
    retention = limits.retention
    return unless retention
    return if plan_changed_at && retention_grace_ends_at > at

    at - retention
  end

  # When a bundle or standalone contract created at +created_at+ is due for deletion (the daily job deletes it
  # on its next run). Nil when the plan keeps documents.
  def retention_deletion_at(created_at)
    retention = limits.retention
    return unless retention

    [ created_at + retention, (retention_grace_ends_at if plan_changed_at) ].compact.max
  end

  private

  def retention_grace_ends_at
    plan_changed_at + PlanLimits.plan_change_grace
  end
end
