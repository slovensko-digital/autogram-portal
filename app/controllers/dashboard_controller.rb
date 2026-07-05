class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    latest_validation_records = current_user.archivation_enabled? ? current_user.contract_validation_records.latest_per_contract : ContractValidationRecord.none

    @expiring_contract_validation_records = latest_validation_records
                                               .expiring
                                               .order(expires_at: :asc)
                                               .limit(5)
    @expiring_contract_validation_records_count = latest_validation_records
                                                              .expiring
                                                              .count
    @bundles_count = current_user.bundles.count
    @contracts_count = current_user.contracts.standalone.count
    @awaiting_my_signature_count = Bundle
                                    .joins(recipients: { recipient_signer: :signer_contracts })
                .merge(Recipient.active.visible)
                                    .where(recipients: { user_id: current_user.id })
                                    .where(signer_contracts: { signed_at: nil, declined_at: nil })
                                    .where.not(user_id: current_user.id)
                                    .distinct
                                    .count
    @awaiting_my_signature_count += FederationRequestInvitation.pending.for_user(current_user).count
    @sent_for_signing_count = current_user.bundles
                                          .joins(recipients: { recipient_signer: :signer_contracts })
                  .merge(Recipient.active.visible)
                                          .where(signer_contracts: { signed_at: nil, declined_at: nil })
                                          .distinct
                                          .count
    @declined_bundles_count = current_user.bundles
                                          .joins(recipients: { recipient_signer: :signer_contracts })
                  .merge(Recipient.active.visible)
                                          .where.not(signer_contracts: { declined_at: nil })
                                          .distinct
                                          .count
    @recent_bundles = current_user.bundles
                                  .includes(:contracts, :recipients, :author)
                                  .order(created_at: :desc)
                                  .limit(5)
  end
end
