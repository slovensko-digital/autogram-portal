json.plan @tenant.plan
json.period do
  json.start @period.begin.iso8601
  json.end @period.end.iso8601
end
json.usage do
  @tenant.usage_summary.each do |entry|
    json.set! entry.limit.to_s.camelize(:lower) do
      json.used entry.used
      json.limit entry.max
    end
  end
end
json.maxDocumentBytes PlanLimits.max_document_bytes
json.retentionDays @tenant.limits.retention&.in_days&.to_i
