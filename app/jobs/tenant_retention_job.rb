# Deletes bundles and documents older than the retention of the tenant's plan (e.g. BASIC_RETENTION_DAYS).
# Tenants whose plan changed recently keep their documents until the grace period
# (PLAN_CHANGE_RETENTION_GRACE_DAYS) passes, e.g. after a cancelled PRO plan (see Tenant::Retention).
class TenantRetentionJob < ApplicationJob
  queue_as :default

  def perform
    Tenant.where(plan: PlanLimits.plans_with_retention).find_each do |tenant|
      cutoff = tenant.retention_cutoff
      delete_expired(tenant, cutoff) if cutoff
    end
  end

  private

  def delete_expired(tenant, cutoff)
    destroy_each(tenant.bundles.where("created_at < ?", cutoff))
    destroy_each(tenant.contracts.standalone.where("created_at < ?", cutoff))
  end

  def destroy_each(scope)
    scope.find_each do |record|
      record.destroy!
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("Retention cleanup failed for #{record.class} #{record.id}: #{e.class}: #{e.message}")
    end
  end
end
