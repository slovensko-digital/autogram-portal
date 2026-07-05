module Notification
  class RecipientSignatureRequestedJob < ApplicationJob
    queue_as :default

    def perform(recipient)
      return unless recipient.sending?
      return if recipient.federated_recipient?
      return if recipient.withdrawn?

      NotificationMailer.with(recipient: recipient).signature_requested(recipient.bundle).deliver_now
      recipient.notified!
    end
  end
end
