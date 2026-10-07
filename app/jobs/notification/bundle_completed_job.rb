module Notification
  class BundleCompletedJob < ApplicationJob
    queue_as :default

    def perform(bundle, signer: nil)
      if bundle.should_notify_author?
        bundle.tenant.notification_recipients(author: bundle.author, except: signer&.user).each do |user|
          NotificationMailer.with(user: user).bundle_completed(bundle).deliver_later
        end
      end
      bundle.webhook&.fire_all_signed
    end
  end
end
