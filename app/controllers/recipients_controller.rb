class RecipientsController < ApplicationController
  before_action :set_bundle
  before_action :set_recipient

  def destroy
    unless @recipient.signed?
      @recipient.destroy
    end

    render turbo_stream: turbo_stream.replace(
      "bundle_recipients_form",
      partial: "bundles/recipients_form",
      locals: { bundle: @bundle }
    )
  end

  def notify
    @recipient.notify!
  end

  private

  def set_bundle
    @bundle = current_user.bundles.find_by_uuid!(params[:bundle_id])
  end

  def set_recipient
    @recipient = @bundle.recipients.find(params[:id])
  end
end
