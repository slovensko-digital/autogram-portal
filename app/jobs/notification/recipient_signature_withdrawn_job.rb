module Notification
  class RecipientSignatureWithdrawnJob < ApplicationJob
    queue_as :default

    def perform(recipient)
      return if recipient.federated_recipient?
      return unless recipient.withdrawn?

      NotificationMailer.with(recipient: recipient).signature_withdrawn(recipient.bundle).deliver_later
    end
  end
end
