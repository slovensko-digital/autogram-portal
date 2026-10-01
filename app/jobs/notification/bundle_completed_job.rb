module Notification
  class BundleCompletedJob < ApplicationJob
    queue_as :default

    def perform(bundle)
      if bundle.should_notify_author?
        bundle.tenant.notification_recipients.each do |user|
          NotificationMailer.with(user: user).bundle_completed(bundle).deliver_later
        end
      end
      bundle.webhook&.fire_all_signed
    end
  end
end
