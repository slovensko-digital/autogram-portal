module Notification
  class ContractSignedJob < ApplicationJob
    queue_as :default

    def perform(contract)
      NotificationMailer.with(user: contract&.user).contract_signed(contract).deliver_later if contract.should_notify_user?
    end
  end
end
