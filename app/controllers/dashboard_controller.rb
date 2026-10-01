class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize :dashboard
    bundles = policy_scope(Bundle)
    contracts = policy_scope(Contract)
    received_bundles = policy_scope([ :received, Bundle ])
    received_invitations = policy_scope([ :received, FederationRequestInvitation ])
    latest_validation_records = policy_scope(ContractValidationRecord).latest_per_contract

    @expiring_contract_validation_records = latest_validation_records
                                               .expiring
                                               .order(expires_at: :asc)
                                               .limit(5)
    @expiring_contract_validation_records_count = latest_validation_records
                                                              .expiring
                                                              .count
    @bundles_count = bundles.count
    @contracts_count = contracts.standalone.count
    @awaiting_my_signature_count = received_bundles
                                    .joins(recipients: { recipient_signer: :signer_contracts })
                .merge(Recipient.active.visible)
                                    .where(recipients: { user_id: current_user.id })
                                    .where(signer_contracts: { signed_at: nil, declined_at: nil })
                                    .distinct
                                    .count
    @awaiting_my_signature_count += received_invitations.pending.count
    @sent_for_signing_count = bundles
                                          .joins(recipients: { recipient_signer: :signer_contracts })
                  .merge(Recipient.active.visible)
                                          .where(signer_contracts: { signed_at: nil, declined_at: nil })
                                          .distinct
                                          .count
    @declined_bundles_count = bundles
                                          .joins(recipients: { recipient_signer: :signer_contracts })
                  .merge(Recipient.active.visible)
                                          .where.not(signer_contracts: { declined_at: nil })
                                          .distinct
                                          .count
    @recent_bundles = bundles
                                  .includes(:contracts, :recipients)
                                  .order(created_at: :desc)
                                  .limit(5)
  end
end
