class TermsOfServiceController < ApplicationController
  skip_before_action :enforce_current_policy_consent

  def index
    redirect_to ENV.fetch("TERMS_OF_SERVICE_URL"), allow_other_host: true if ENV["TERMS_OF_SERVICE_URL"].present?
  end
end
