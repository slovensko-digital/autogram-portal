# Usage limits of the tenant plans and the instance, configured through ENV so that every
# portal instance can match its own price list. A blank or missing value means "unlimited"
# (or "never deleted" for retention); the only built-in default keeps Basic at one member.
#
#   BASIC_MAX_MEMBERS, BASIC_MAX_STORED_DOCUMENTS, BASIC_STORAGE_GB,
#   BASIC_MONTHLY_SIGNATURE_REQUESTS, BASIC_MONTHLY_TIMESTAMPS, BASIC_RETENTION_DAYS
#   (and the same with the PRO_ prefix)
#   MAX_DOCUMENT_SIZE_MB, ANONYMOUS_RETENTION_MINUTES, PLAN_CHANGE_RETENTION_GRACE_DAYS,
#   SIGNED_HISTORY_DAYS
#
# Values are read on every call, so tests can change ENV without resetting anything.
module PlanLimits
  Limits = Data.define(
    :max_members,
    :max_stored_documents,
    :storage_bytes,
    :monthly_signature_requests,
    :monthly_timestamps,
    :retention
  )

  PLAN_DEFAULTS = {
    "basic" => { "MAX_MEMBERS" => 1 }
  }.freeze

  DEFAULT_ANONYMOUS_RETENTION_MINUTES = 55
  DEFAULT_PLAN_CHANGE_RETENTION_GRACE_DAYS = 30

  def self.for(plan)
    plan = plan.to_s
    Limits.new(
      max_members: plan_integer(plan, "MAX_MEMBERS"),
      max_stored_documents: plan_integer(plan, "MAX_STORED_DOCUMENTS"),
      storage_bytes: plan_integer(plan, "STORAGE_GB")&.gigabytes,
      monthly_signature_requests: plan_integer(plan, "MONTHLY_SIGNATURE_REQUESTS"),
      monthly_timestamps: plan_integer(plan, "MONTHLY_TIMESTAMPS"),
      retention: plan_integer(plan, "RETENTION_DAYS")&.days
    )
  end

  # Plans whose documents are deleted after a retention period.
  def self.plans_with_retention
    Tenant.plans.keys.select { |plan| self.for(plan).retention }
  end

  def self.max_document_bytes
    integer("MAX_DOCUMENT_SIZE_MB")&.megabytes
  end

  def self.anonymous_retention
    (integer("ANONYMOUS_RETENTION_MINUTES") || DEFAULT_ANONYMOUS_RETENTION_MINUTES).minutes
  end

  # How long documents of a tenant are kept after its plan changed (e.g. PRO cancelled) before
  # the retention of the new plan applies to them.
  def self.plan_change_grace
    (integer("PLAN_CHANGE_RETENTION_GRACE_DAYS") || DEFAULT_PLAN_CHANGE_RETENTION_GRACE_DAYS).days
  end

  # How far back a user sees documents they signed for others while working in a tenant whose
  # plan has a retention period.
  def self.signed_history
    integer("SIGNED_HISTORY_DAYS")&.days
  end

  def self.plan_integer(plan, key)
    name = "#{plan.upcase}_#{key}"
    ENV.key?(name) ? integer(name) : PLAN_DEFAULTS.dig(plan, key)
  end
  private_class_method :plan_integer

  def self.integer(name)
    value = ENV[name].to_s.strip
    return if value.empty?

    Integer(value, 10).clamp(0..)
  rescue ArgumentError
    Rails.logger.warn("Ignoring invalid #{name}=#{ENV[name].inspect}")
    nil
  end
  private_class_method :integer
end
