class Api::Federation::V1::RequestInvitationsController < FederationApiController
  before_action :set_invitation, only: [ :withdraw ]

  def create
    invitation_attributes = invitation_params

    @invitation = FederationRequestInvitation.find_or_initialize_by(
      portal_instance: current_portal_instance,
      origin_recipient_uuid: invitation_attributes.fetch(:recipientId)
    )

    @invitation.assign_attributes(
      origin_bundle_uuid: invitation_attributes.fetch(:bundleId),
      recipient_email: invitation_attributes.fetch(:recipientEmail),
      payload: invitation_attributes.to_h,
      status: "pending",
      withdrawn_at: nil
    )
    @invitation.save!

    render json: { invitation: invitation_payload(@invitation) }, status: :created
  end

  def withdraw
    @invitation.resolve!(status: resolved_status)

    render json: { invitation: invitation_payload(@invitation) }
  end

  private

  def required_scope
    action_name == "withdraw" ? "federation.request.invitation.withdraw" : "federation.request.invitation.send"
  end

  def set_invitation
    @invitation = FederationRequestInvitation.find_by!(
      portal_instance: current_portal_instance,
      origin_recipient_uuid: params[:recipient_uuid]
    )
  end

  def invitation_params
    params.require(:invitation).permit(
      :recipientId,
      :bundleId,
      :recipientEmail,
      :authorName,
      :note,
      :openUrl,
      :status,
      :signingRule,
      :requiredSignatures,
      originPortal: [ :issuer, :name ],
      contracts: [ :id, :displayName ]
    )
  end

  def invitation_payload(invitation)
    {
      id: invitation.uuid,
      recipientId: invitation.origin_recipient_uuid,
      bundleId: invitation.origin_bundle_uuid,
      recipientEmail: invitation.recipient_email,
      status: invitation.status,
      createdAt: invitation.created_at.iso8601,
      withdrawnAt: invitation.withdrawn_at&.iso8601
    }
  end

  def resolved_status
    params.permit(:status)[:status].presence || "withdrawn"
  end
end
