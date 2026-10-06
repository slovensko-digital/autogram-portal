class DashboardController < ApplicationController
  AWAITING_LIMIT = 5
  RECENT_LIMIT = 5

  AwaitingItem = Data.define(:name, :received_at, :signatures, :portal, :path)

  before_action :authenticate_user!

  def index
    authorize :dashboard
    bundles = policy_scope(Bundle)
    contracts = policy_scope(Contract)
    latest_validation_records = policy_scope(ContractValidationRecord).latest_per_contract

    @expiring_contract_validation_records = latest_validation_records
                                               .expiring
                                               .order(expires_at: :asc)
                                               .limit(5)
    @expiring_contract_validation_records_count = latest_validation_records
                                                              .expiring
                                                              .count
    load_awaiting_my_signature
    @bundles_count = bundles.count
    @contracts_count = contracts.standalone.count
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
                                  .limit(RECENT_LIMIT)
                                  .to_a
    return unless current_tenant.pro?

    @personal_bundle_ids = bundles.where(id: @recent_bundles.map(&:id)).recipient_user(current_user).distinct.pluck(:id).to_set
  end

  private

  # Bundles and trusted-portal invitations the signed-in user still has to sign, newest first.
  def load_awaiting_my_signature
    awaiting_bundles = policy_scope([ :received, Bundle ]).distinct.awaiting_signature_of(current_user)
    pending_invitations = policy_scope([ :received, FederationRequestInvitation ]).pending

    @awaiting_my_signature_count = awaiting_bundles.count + pending_invitations.count

    latest_bundles = awaiting_bundles.order(created_at: :desc).limit(AWAITING_LIMIT).to_a
    recipients = Recipient.active.visible.where(user: current_user, bundle_id: latest_bundles.map(&:id)).index_by(&:bundle_id)
    bundle_items = latest_bundles.map do |bundle|
      AwaitingItem.new(
        name: bundle.display_name,
        received_at: bundle.created_at,
        signatures: "#{bundle.completed_recipients.size} / #{bundle.visible_recipients.size}",
        portal: nil,
        path: sign_bundle_path(bundle, recipient: recipients[bundle.id]&.uuid)
      )
    end

    invitation_items = pending_invitations.includes(:portal_instance).order(created_at: :desc).limit(AWAITING_LIMIT).map do |invitation|
      payload = invitation.payload
      AwaitingItem.new(
        name: t("bundles.received.external_invitation_title"),
        received_at: invitation.created_at,
        signatures: nil,
        portal: invitation.portal_instance.name,
        path: federation_requests_open_path(url: payload["openUrl"])
      )
    end

    @awaiting_my_signature = (bundle_items + invitation_items).sort_by(&:received_at).reverse.first(AWAITING_LIMIT)
  end
end
