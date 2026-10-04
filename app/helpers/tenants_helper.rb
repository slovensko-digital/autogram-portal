module TenantsHelper
  # A pill with the tenant's plan; PRO stands out.
  def tenant_plan_badge(tenant, label: t("tenants.plans.#{tenant.plan}"), size: "px-2 py-0.5 text-xs")
    colors = tenant.pro? ? "bg-violet-100 text-violet-700" : "bg-gray-100 text-gray-600"
    tag.span(label, class: "shrink-0 rounded-full font-semibold #{size} #{colors}")
  end

  # A usage value (Tenant::Usage::UsageEntry#used or #max) in the unit of its limit.
  def plan_usage_value(limit, value)
    limit == :storage ? PlanLimits::Exceeded.format(limit, value) : number_with_delimiter(value)
  end

  # "3 / 10", or "3 (unlimited)" for a limit the plan does not have.
  def plan_usage_text(entry)
    used = plan_usage_value(entry.limit, entry.used)
    return t("tenants.usage.unlimited_value", used: used) if entry.unlimited?

    t("tenants.usage.limited_value", used: used, max: plan_usage_value(entry.limit, entry.max))
  end
end
