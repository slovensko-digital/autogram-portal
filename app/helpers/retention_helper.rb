module RetentionHelper
  # Whether a document due for deletion at +deletion_at+ should be pointed out as about to be deleted.
  def deletion_soon?(deletion_at)
    deletion_at.present? && deletion_at <= Tenant::Retention::EXPIRING_SOON.from_now
  end

  # "today", "tomorrow" or "in 5 days"; a document past its date is deleted on the next run of the job.
  def deletion_countdown(deletion_at)
    days = [ (deletion_at.to_date - Date.current).to_i, 0 ].max
    case days
    when 0 then t("retention.countdown.today")
    when 1 then t("retention.countdown.tomorrow")
    else t("retention.countdown.days", count: days)
    end
  end

  def deletion_date(deletion_at)
    deletion_at.strftime("%d.%m.%Y")
  end
end
