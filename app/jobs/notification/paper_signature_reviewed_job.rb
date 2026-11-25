module Notification
  class PaperSignatureReviewedJob < ApplicationJob
    queue_as :default

    def perform(paper_signature)
      recipient = paper_signature.recipient
      return if recipient.email.blank? || recipient.federated_recipient?

      if paper_signature.approved?
        NotificationMailer.with(recipient: recipient).paper_signature_approved(paper_signature).deliver_later
      elsif paper_signature.returned?
        NotificationMailer.with(recipient: recipient).paper_signature_returned(paper_signature).deliver_later
      end
    end
  end
end
