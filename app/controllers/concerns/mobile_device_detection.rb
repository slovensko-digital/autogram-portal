# Autogram batch signing needs the desktop app, so phones are offered signing one document at a time.
module MobileDeviceDetection
  extend ActiveSupport::Concern

  MOBILE_DEVICE_USER_AGENT = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i

  included do
    helper_method :mobile_device_request?
  end

  private

  def mobile_device_request?
    request.user_agent.to_s.match?(MOBILE_DEVICE_USER_AGENT)
  end
end
