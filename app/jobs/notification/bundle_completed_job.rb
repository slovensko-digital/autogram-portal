module Notification
  class BundleCompletedJob < ApplicationJob
    queue_as :default

    def perform(bundle)
      NotificationMailer.with(user: bundle.author).bundle_completed(bundle).deliver_later if bundle.should_notify_author?
      bundle.webhook&.fire_all_signed
    end
  end
end
