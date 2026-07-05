module Federation
  class SendRequestInvitationJob < ApplicationJob
    queue_as :default

    retry_on FederationRequestBroker::Error, wait: :polynomially_longer, attempts: 5

    def perform(recipient)
      return unless recipient.sending?
      return unless recipient.federated_recipient?
      return if recipient.withdrawn?

      FederationPortalClient.new.send_request_invitation(
        portal_instance: recipient.portal_instance,
        invitation: invitation_payload(recipient)
      )

      recipient.update!(remote_notified_at: Time.current)
      recipient.notified!
    end

    private

    def invitation_payload(recipient)
      {
        recipientId: recipient.uuid,
        bundleId: recipient.bundle.uuid,
        originPortal: {
          issuer: FederationConfiguration.static_issuer,
          name: FederationConfiguration.portal_name
        },
        authorName: recipient.bundle.author.display_name,
        recipientEmail: recipient.email,
        status: "awaiting",
        contracts: recipient.bundle.contracts.map do |contract|
          {
            id: contract.uuid,
            displayName: contract.display_name
          }
        end,
        signingRule: recipient.bundle.signing_rule,
        requiredSignatures: recipient.bundle.required_signatures,
        note: recipient.bundle.note,
        openUrl: open_url(recipient)
      }
    end

    def open_url(recipient)
      "#{FederationConfiguration.static_base_url}#{Rails.application.routes.url_helpers.sign_bundle_path(recipient.bundle, recipient: recipient.uuid)}"
    end
  end
end
