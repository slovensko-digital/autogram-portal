class Federation::RequestsController < ApplicationController
  before_action :authenticate_user!, only: [ :claim ]

  def show
    @request_url = params[:url].to_s
    return if @request_url.blank?

    preview = federation_request_broker.preview(url: @request_url)
    @origin_portal = preview.portal_instance
    @request_preview = preview.request
  rescue FederationRequestBroker::Error => e
    @preview_error = e.message
  end

  def claim
    sign_url = federation_request_broker.claim(
      url: params.require(:url),
      claimant: {
        email: current_user.email,
        display_name: current_user.display_name,
        external_user_id: current_user.id.to_s
      }
    )

    redirect_to sign_url, allow_other_host: true
  rescue FederationRequestBroker::Error => e
    redirect_to federation_requests_open_path(url: params[:url]), alert: e.message
  end

  private

  def federation_request_broker
    @federation_request_broker ||= FederationRequestBroker.new
  end
end
