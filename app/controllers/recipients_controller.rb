class RecipientsController < ApplicationController
  before_action :set_bundle
  before_action :set_portal_instances
  before_action :set_recipient, except: [ :create, :index, :notify_all ]
  before_action :skip_policy_scope, only: [ :index ]

  rescue_from Pundit::NotAuthorizedError, with: :render_tenant_record_denial

  def index
  end

  def create
    @recipient = @bundle.recipients.build(recipient_params)

    if @recipient.save
      @success_message = t("recipients.index.added", recipient: @recipient.display_name)
      render "index"
    else
      render "index", locals: { recipient_error: @recipient.errors.full_messages.join(", ") }
    end
  end

  def destroy
    if @recipient.removable?
      @recipient.withdraw!
      @success_message = t("recipients.index.withdrawn", recipient: @recipient.display_name)
    else
      @error_message = t("recipients.index.withdraw_failed", recipient: @recipient.display_name)
    end

    render "index"
  end

  def notify
    if @recipient.notifiable?
      begin
        @recipient.notify!
        @success_message = t("recipients.index.invitation_sending", recipient: @recipient.display_name)
      rescue PlanLimits::Exceeded => e
        @error_message = e.message
      end
    else
      @error_message = t("recipients.index.invitation_failed", recipient: @recipient.display_name)
    end

    render "index"
  end

  # Sends the invitation to every recipient who has not received it yet.
  def notify_all
    recipients = @bundle.active_recipients.order(:created_at).select(&:notifiable?)

    if recipients.empty?
      @error_message = t("recipients.index.invitations_none")
    else
      begin
        recipients.each(&:notify!)
        @success_message = t("recipients.index.invitations_sending", count: recipients.size)
      rescue PlanLimits::Exceeded => e
        @error_message = e.message
      end
    end

    render "index"
  end

  private

  def set_bundle
    @bundle = Bundle.find_by_uuid!(params[:bundle_id])
    authorize @bundle, :manage_recipients?
  end

  def set_recipient
    @recipient = @bundle.recipients.find_by_uuid!(params[:id])
  end

  def set_portal_instances
    @portal_instances = PortalInstance.trusted.order(:name)
  end

  def recipient_params
    params.require(:recipient).permit(:email, :mobile_phone, :portal_instance_uuid)
  end
end
