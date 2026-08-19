module Notification
  class BundleCompletedJob < ApplicationJob
    queue_as :default

    def perform(bundle)
      bundle.webhook&.fire_all_signed
    end
  end
end
