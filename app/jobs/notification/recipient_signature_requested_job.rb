module Notification
  class RecipientSignatureRequestedJob < ApplicationJob
    queue_as :default

    def perform(recipient)
      NotificationMailer.with(recipient: recipient).signature_requested(recipient.bundle).deliver_now
      recipient.update!(status: :notified)
    end
  end
end
