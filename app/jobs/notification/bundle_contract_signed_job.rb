module Notification
  class BundleContractSignedJob < ApplicationJob
    queue_as :default

    def perform(bundle, contract, signer: nil)
      NotificationMailer.with(user: bundle.author).bundle_contract_signed(bundle, contract, signer).deliver_later if bundle.should_notify_author?(signer: signer) && bundle.completed? == false
      bundle.webhook&.fire_contract_signed(contract)
    end
  end
end
