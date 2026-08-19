module Notification
  class ContractSignedJob < ApplicationJob
    queue_as :default

    def perform(contract, signer: nil)
    end
  end
end
