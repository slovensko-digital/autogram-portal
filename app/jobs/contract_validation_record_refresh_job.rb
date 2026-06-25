class ContractValidationRecordRefreshJob < ApplicationJob
  queue_as :default

  def perform(record_id)
    record = ContractValidationRecord.includes(:contract, :contract_content_version).find_by(id: record_id)
    return if record.blank?
    return unless record.user&.archivation_enabled?
    return unless record.refreshable?

    record.contract.with_lock do
      record.reload
      return unless record.refreshable?

      record.contract.extend_signatures!(target_level: "LTA", source_content_version: record.contract_content_version)
    end
  rescue StandardError => e
    Rails.logger.warn("Contract validation record refresh failed for record #{record_id}: #{e.class}: #{e.message}")
  end
end
