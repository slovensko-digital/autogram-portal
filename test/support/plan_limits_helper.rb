# Sets plan limit ENV variables (see PlanLimits) for the duration of a block.
module PlanLimitsHelper
  def with_plan_limits(vars)
    previous_values = vars.keys.index_with { |key| ENV[key] }
    vars.each { |key, value| ENV[key] = value&.to_s }
    yield
  ensure
    previous_values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
