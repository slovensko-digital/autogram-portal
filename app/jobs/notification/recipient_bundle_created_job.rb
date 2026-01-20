module Notification
  class RecipientBundleCreatedJob < ApplicationJob
    queue_as :default

    def perform(recipient)
      NotificationMailer.with(recipient: recipient).bundle_created(recipient.bundle).deliver_now
      recipient.update!(status: :notified)
    end
  end
end
