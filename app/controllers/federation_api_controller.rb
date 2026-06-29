class FederationApiController < ActionController::API
  before_action :authenticate_portal!
  before_action :set_json_format

  rescue_from JWT::DecodeError, with: :render_unauthorized
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_bad_request

  attr_reader :current_portal_assertion

  def current_portal_instance
    current_portal_assertion&.portal_instance
  end

  private

  def authenticate_portal!
    @current_portal_assertion = PortalAssertionAuthenticator.new.verify_token(
      authenticity_token,
      audience: FederationConfiguration.issuer(request: request),
      required_scope: required_scope
    )
  end

  def authenticity_token
    (ActionController::HttpAuthentication::Token.token_and_options(request)&.first&.gsub("Bearer ", "") || params[:token])&.squish.presence
  end

  def required_scope
    raise NotImplementedError
  end

  def render_bad_request(exception)
    render status: :bad_request, json: { message: exception.message }
  end

  def render_unauthorized(exception = nil)
    headers["WWW-Authenticate"] = 'Token realm="Federation API"'
    render status: :unauthorized, json: { message: exception&.message || "Unauthorized federation credentials" }
  end

  def render_not_found
    render status: :not_found, json: { message: "Not found" }
  end

  def set_json_format
    request.format = :json
  end
end
