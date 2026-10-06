module TenantsHelper
  # A pill with the tenant's plan; PRO stands out.
  def tenant_plan_badge(tenant, label: t("tenants.plans.#{tenant.plan}"), size: "px-2 py-0.5 text-xs")
    colors = tenant.pro? ? "bg-violet-100 text-violet-700" : "bg-gray-100 text-gray-600"
    tag.span(label, class: "shrink-0 rounded-full font-semibold #{size} #{colors}")
  end

  # Without the archivation feature the LTA extension only adds an archive timestamp, so its labels
  # have a `<key>_without_archivation` variant. Keys without one (e.g. the T level) are shared.
  def archive_action_t(tenant, key)
    tenant&.archivation_enabled? ? t(key) : t("#{key}_without_archivation", default: key.to_sym)
  end

  # A usage value (Tenant::Usage::UsageEntry#used or #max) in the unit of its limit.
  def plan_usage_value(limit, value)
    limit == :storage ? PlanLimits::Exceeded.format(limit, value) : number_with_delimiter(value)
  end

  # "3 / 10", or "3 (unlimited)" for a limit the plan does not have; spoken: "3 of 10" for screen readers.
  def plan_usage_text(entry, spoken: false)
    used = plan_usage_value(entry.limit, entry.used)
    return t("tenants.usage.unlimited_value", used: used) if entry.unlimited?

    t(spoken ? "tenants.usage.limited_value_spoken" : "tenants.usage.limited_value", used: used, max: plan_usage_value(entry.limit, entry.max))
  end
end
