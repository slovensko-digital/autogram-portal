class ApiTokenUsesCleanupJob < ApplicationJob
  queue_as :default

  def perform
    ApiTokenUse.expired.delete_all
  end
end
