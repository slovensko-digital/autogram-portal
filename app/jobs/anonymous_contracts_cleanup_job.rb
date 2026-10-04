class AnonymousContractsCleanupJob < ApplicationJob
  queue_as :default

  def perform
    Contract.anonymous.where("created_at < ?", PlanLimits.anonymous_retention.ago).find_each(&:destroy)
  end
end
