module Notification
  class RecipientNoLongerRequiredJob < ApplicationJob
    queue_as :default

    def perform(recipient)
      return if recipient.federated_recipient?

      NotificationMailer.with(recipient: recipient).signature_no_longer_required(recipient.bundle).deliver_later
    end
  end
end
