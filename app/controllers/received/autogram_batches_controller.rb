# Signs every document awaiting the signed-in user in the bundles they received in one Autogram batch,
# whichever organization sent them.
class Received::AutogramBatchesController < ApplicationController
  include MobileDeviceDetection

  def show
    authorize [ :received, Bundle ], :autogram_batch?
    batch = AwaitingBatchSigning.new(policy_scope([ :received, Bundle ]).distinct.awaiting_signature_of(current_user), user: current_user)

    if mobile_device_request? || !batch.available?
      return redirect_to received_bundles_path(state: "awaiting"),
                         alert: t(mobile_device_request? ? "bundles.autogram_batch.desktop_only" : ".unavailable")
    end

    @batch_items = batch.items.map { |item| batch_item(item) }
    @other_items_count = batch.other_items.size
  end

  private

  def batch_item(item)
    contract = item.contract
    session = item.signer_contract.pending_autogram_session!
    session_token = SessionAccessToken.generate(contract: contract, session: session)

    {
      contract_id: contract.uuid,
      contract_name: contract.display_name.to_s,
      bundle_name: item.bundle.display_name,
      sender: item.bundle.sender_display_name,
      parameters_path: parameters_contract_session_path(contract, session, session_token: session_token),
      upload_path: upload_contract_session_path(contract, session, session_token: session_token)
    }
  end
end
