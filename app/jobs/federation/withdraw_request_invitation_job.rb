module Federation
  class WithdrawRequestInvitationJob < ApplicationJob
    queue_as :default

    retry_on FederationRequestBroker::Error, wait: :polynomially_longer, attempts: 5

    def perform(recipient)
      return unless recipient.federated_recipient?
      return unless recipient.remote_notified_at.present?

      FederationPortalClient.new.withdraw_request_invitation(
        portal_instance: recipient.portal_instance,
        recipient_uuid: recipient.uuid
      )
    end
  end
end