class TermsOfServiceController < ApplicationController
  def index
    redirect_to ENV.fetch("TERMS_OF_SERVICE_URL"), allow_other_host: true if ENV["TERMS_OF_SERVICE_URL"].present?
  end
end
