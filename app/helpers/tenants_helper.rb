module TenantsHelper
  # A pill with the tenant's plan; PRO stands out.
  def tenant_plan_badge(tenant, label: t("tenants.plans.#{tenant.plan}"), size: "px-2 py-0.5 text-xs")
    colors = tenant.pro? ? "bg-violet-100 text-violet-700" : "bg-gray-100 text-gray-600"
    tag.span(label, class: "shrink-0 rounded-full font-semibold #{size} #{colors}")
  end
end
