# Raised when an operation does not fit a plan limit (see Tenant::Usage) or the document size limit.
class PlanLimits::Exceeded < StandardError
  attr_reader :limit, :max, :used

  def initialize(limit:, max:, used: nil)
    @limit = limit
    @max = max
    @used = used
    super(I18n.t("plan_limits.exceeded.#{limit}", max: self.class.format(limit, max), used: self.class.format(limit, used)))
  end

  def self.format(limit, value)
    return value unless value && %i[storage document_size].include?(limit)

    ActiveSupport::NumberHelper.number_to_human_size(value, strip_insignificant_zeros: true)
  end
end
