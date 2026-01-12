module Eidentita
  class SessionCleanupJob < ApplicationJob
    queue_as :default

    def perform
      EidentitaSession.where("created_at < ?", 2.hours.ago).destroy_all
    end
  end
end
