class Api::Federation::V1::RequestsController < FederationApiController
  before_action :set_recipient
  before_action :authorize_portal_for_recipient!
  before_action :ensure_claimable_state!, only: [ :show, :claim ]

  def show
    if params[:bundleId].present? && @recipient.bundle.uuid != params[:bundleId]
      return render json: { message: "Not found" }, status: :not_found
    end

    render json: { request: request_payload }
  end

  def claim
    claimant = params.require(:claimant).permit(:email, :displayName, :externalUserId)

    unless @recipient.email.to_s.casecmp?(claimant.fetch(:email))
      return render json: { message: "Claimant email does not match recipient" }, status: :unprocessable_entity
    end

    @recipient.update!(
      remote_claimed_at: Time.current,
      remote_claimed_by_email: claimant.fetch(:email)
    )

    grant = RecipientAccessGrant.issue!(
      recipient: @recipient,
      portal_instance: current_portal_instance,
      claimed_by_email: claimant.fetch(:email),
      claimed_by_external_user_id: claimant[:externalUserId],
      claim_jti: current_portal_assertion.payload.fetch("jti")
    )

    render json: {
      claim: {
        recipientId: @recipient.uuid,
        claimedAt: @recipient.remote_claimed_at.iso8601,
        signUrl: sign_url(grant: grant.raw_token),
        bundleId: @recipient.bundle.uuid,
        expiresAt: grant.expires_at.iso8601
      }
    }, status: :created
  end

  private

  def required_scope
    action_name == "claim" ? "federation.request.claim" : "federation.request.read"
  end

  def set_recipient
    @recipient = Recipient.find_by!(uuid: params[:id])
  end

  def authorize_portal_for_recipient!
    return if @recipient.federated_recipient? && @recipient.portal_instance == current_portal_instance

    render json: { message: "Portal is not authorized for this recipient" }, status: :forbidden
  end

  def ensure_claimable_state!
    return if @recipient.active? && !@recipient.superseded? && !@recipient.signed?

    render json: { message: "Request is no longer claimable" }, status: :conflict
  end

  def request_payload
    {
      recipientId: @recipient.uuid,
      bundleId: @recipient.bundle.uuid,
      originPortal: {
        issuer: FederationConfiguration.issuer(request: request),
        name: FederationConfiguration.portal_name
      },
      authorName: @recipient.bundle.author.display_name,
      recipientEmail: @recipient.email,
      recipientPortalId: @recipient.portal_instance.uuid,
      status: "awaiting",
      contracts: @recipient.bundle.contracts.map do |contract|
        {
          id: contract.uuid,
          displayName: contract.display_name
        }
      end,
      signingRule: @recipient.bundle.signing_rule,
      requiredSignatures: @recipient.bundle.required_signatures,
      note: @recipient.bundle.note,
      openUrl: sign_url
    }
  end

  def sign_url(grant: nil)
    query = grant.present? ? { grant: grant } : { recipient: @recipient.uuid }
    "#{request.base_url}#{sign_bundle_path(@recipient.bundle, **query)}"
  end
end
