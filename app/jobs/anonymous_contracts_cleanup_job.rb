class AnonymousContractsCleanupJob < ApplicationJob
  queue_as :default

  def perform
    Contract.anonymous.where("created_at < ?", 30.minutes.ago).find_each(&:destroy)
  end
end
