module Notification
  class BundleContractSignedJob < ApplicationJob
    queue_as :default

    def perform(bundle, contract)
      bundle.webhook&.fire_contract_signed(contract)
    end
  end
end
