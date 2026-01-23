class SdkController < ActionController::Base
  include Rails.application.routes.url_helpers

  skip_before_action :verify_authenticity_token

  def sdk
    respond_to do |format|
      format.js { render "sdk/sdk", content_type: "application/javascript" }
    end
  end
end
