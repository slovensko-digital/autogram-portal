module Notification
  class ContractSignedJob < ApplicationJob
    queue_as :default

    def perform(contract, signer: nil)
      NotificationMailer.with(user: contract&.user).contract_signed(contract, signer).deliver_later if contract.should_notify_user?
    end
  end
end
