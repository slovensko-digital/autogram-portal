class PrivacyPolicyController < ApplicationController
  def index
    redirect_to ENV.fetch("PRIVACY_POLICY_URL"), allow_other_host: true if ENV["PRIVACY_POLICY_URL"].present?
  end
end
