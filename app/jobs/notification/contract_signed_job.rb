module Notification
  class ContractSignedJob < ApplicationJob
    queue_as :default

    def perform(contract, signer: nil, except: signer&.user)
      return unless contract.should_notify_author?

      contract.tenant.notification_recipients(author: contract.author, except: except).each do |user|
        NotificationMailer.with(user: user).contract_signed(contract, signer).deliver_later
      end
    end
  end
end
