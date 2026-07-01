class RecipientsController < ApplicationController
  before_action :set_bundle
  before_action :set_portal_instances
  before_action :set_recipient, except: [ :create, :index ]

  def index
  end

  def create
    @recipient = @bundle.recipients.build(recipient_params)

    if @recipient.save
      render "index"
    else
      render "index", locals: { recipient_error: @recipient.errors.full_messages.join(", ") }
    end
  end

  def destroy
    @recipient.withdraw!

    render "index"
  end

  def notify
    @recipient.notify!
    render "index"
  end

  private

  def set_bundle
    @bundle = current_user.bundles.find_by_uuid!(params[:bundle_id])
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
