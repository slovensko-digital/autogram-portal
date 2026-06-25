class ContractValidationRecordsMaintenanceJob < ApplicationJob
  queue_as :default

  def perform
    ContractValidationRecord
      .joins(:user)
      .merge(User.with_feature(:archivation))
      .latest_per_contract
      .includes(:contract, :contract_content_version)
      .expiring
      .find_each do |record|
        next unless record.refreshable?

        ContractValidationRecordRefreshJob.perform_later(record.id)
      end
  end
end
