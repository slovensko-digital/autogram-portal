module Notification
  class RecipientNoLongerRequiredJob < ApplicationJob
    queue_as :default

    def perform(recipient)
      return unless recipient.bundle.author.feature_enabled?(:real_emails)

      NotificationMailer.with(recipient: recipient).signature_no_longer_required(recipient.bundle).deliver_later
    end
  end
end
