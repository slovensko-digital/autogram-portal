module Notification
  class BundleCreatedJob < ApplicationJob
    queue_as :default

    def perform(bundle)
      bundle.recipients.each do |recipient|
        NotificationMailer.with(recipient: recipient).bundle_created(bundle).deliver_later
      end
    end
  end
end
