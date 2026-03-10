class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    @bundles_count = current_user.bundles.count
    @contracts_count = current_user.contracts.count
    @awaiting_my_signature_count = Contract.awaiting_signature_for(current_user).count
    @sent_for_signing_count = current_user.bundles
                                          .joins(recipients: { recipient_signer: :signer_contracts })
                                          .where(recipients: { status: :pending })
                                          .where(signer_contracts: { signed_at: nil })
                                          .distinct
                                          .count
    @declined_bundles_count = current_user.bundles
                                          .joins(:recipients)
                                          .where(recipients: { status: :declined })
                                          .distinct
                                          .count
    @recent_bundles = current_user.bundles
                                  .includes(:contracts, :recipients, :author)
                                  .order(created_at: :desc)
                                  .limit(5)
  end
end
