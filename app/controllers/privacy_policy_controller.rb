class PrivacyPolicyController < ApplicationController
  skip_before_action :enforce_current_policy_consent

  def index
    redirect_to ENV.fetch("PRIVACY_POLICY_URL"), allow_other_host: true if ENV["PRIVACY_POLICY_URL"].present?
  end
end
