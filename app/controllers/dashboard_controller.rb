class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @bundles_count = current_user.bundles.count
    @contracts_count = current_user.contracts.standalone.count
    @awaiting_my_signature_count = Bundle
                                    .joins(recipients: { recipient_signer: :signer_contracts })
                                    .where(recipients: { user_id: current_user.id })
                                    .where(signer_contracts: { signed_at: nil, declined_at: nil })
                                    .where.not(user_id: current_user.id)
                                    .distinct
                                    .count
    @sent_for_signing_count = current_user.bundles
                                          .joins(recipients: { recipient_signer: :signer_contracts })
                                          .where(signer_contracts: { signed_at: nil, declined_at: nil })
                                          .distinct
                                          .count
    @declined_bundles_count = current_user.bundles
                                          .joins(recipients: { recipient_signer: :signer_contracts })
                                          .where.not(signer_contracts: { declined_at: nil })
                                          .distinct
                                          .count
    @recent_bundles = current_user.bundles
                                  .includes(:contracts, :recipients, :author)
                                  .order(created_at: :desc)
                                  .limit(5)
  end
end
