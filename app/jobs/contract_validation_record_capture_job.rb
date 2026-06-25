class ContractValidationRecordCaptureJob < ApplicationJob
  queue_as :default
  retry_on ActiveStorage::FileNotFoundError, Errno::ENOENT, wait: 1.second, attempts: 5

  def perform(contract_id)
    contract = Contract.find_by(id: contract_id)
    return if contract.blank?

    contract.send(:capture_existing_signed_content!)
  end
end
