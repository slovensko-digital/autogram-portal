module Notification
  class BundleContractSignedJob < ApplicationJob
    queue_as :default

    def perform(bundle, contract, signer: nil)
      if bundle.should_notify_author? && bundle.completed? == false
        bundle.tenant.notification_recipients(author: bundle.author, except: signer&.user).each do |user|
          NotificationMailer.with(user: user).bundle_contract_signed(bundle, contract, signer).deliver_later
        end
      end
      bundle.webhook&.fire_contract_signed(contract)
    end
  end
end
