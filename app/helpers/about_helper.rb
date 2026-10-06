module AboutHelper
  # Limits of the Basic plan as configured for this instance (see PlanLimits), for the price list.
  def basic_plan_limit_items
    limits = PlanLimits.for(:basic)
    {
      stored_documents: limits.max_stored_documents,
      signature_requests: limits.monthly_signature_requests,
      timestamps: limits.monthly_timestamps
    }.filter_map { |key, count| t("about.index.start_using.basic.limits.#{key}", count: count) if count }
  end

  def basic_plan_retention_item
    retention = PlanLimits.for(:basic).retention
    t("about.index.start_using.basic.limits.retention", count: retention.in_days.to_i) if retention
  end

  def basic_plan_members_item
    max_members = PlanLimits.for(:basic).max_members
    t("about.index.start_using.basic.limits.members", count: max_members) if max_members
  end

  def faq_answer(key, item)
    retention = PlanLimits.for(:basic).retention
    return item[:answer] unless key.to_s == "storage" && retention

    "#{item[:answer]} #{t('about.index.faq.storage_basic_retention', count: retention.in_days.to_i)}"
  end
end
