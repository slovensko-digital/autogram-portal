module Notification
  class RecipientSignatureRequestedJob < ApplicationJob
    queue_as :default

    def perform(recipient)
      NotificationMailer.with(recipient: recipient).signature_requested(recipient.bundle).deliver_now
      recipient.notified!
    end
  end
end
