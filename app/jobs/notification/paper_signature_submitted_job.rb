module Notification
  # Asking for the review is an action request, so it does not depend on the author's notification
  # settings or on a webhook taking over the notifications.
  class PaperSignatureSubmittedJob < ApplicationJob
    queue_as :default

    def perform(paper_signature)
      return unless paper_signature.submitted?

      bundle = paper_signature.contract.bundle
      bundle.tenant.notification_recipients(author: bundle.author).each do |user|
        NotificationMailer.with(user: user).paper_signature_submitted(paper_signature).deliver_later
      end
    end
  end
end
