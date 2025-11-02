class ApiController < ApplicationController
  protect_from_forgery with: :null_session
  before_action :authenticate_user!

  rescue_from JWT::DecodeError do |error|
    render_unauthorized("API token")
  end

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::ParameterMissing, with: :render_bad_request

  def current_user
    @current_user
  end

  private

  def authenticate_user!
    @current_user = ApiEnvironment.token_authenticator.verify_token(authenticity_token)
  rescue JWT::VerificationError, JWT::InvalidSubError => error
    render_unauthorized(error.message)
  end

  def authenticity_token
    (ActionController::HttpAuthentication::Token.token_and_options(request)&.first&.gsub("Bearer ", "") || params[:token])&.squish.presence
  end

  def render_bad_request(exception)
    render status: :bad_request, json: { message: exception.message }
  end

  def render_unauthorized(key = "credentials")
    headers["WWW-Authenticate"] = 'Token realm="API"'
    render status: :unauthorized, json: { message: "Unauthorized " + key }
  end

  def render_not_found
    render status: :not_found, json: { message: "Not found" }
  end
end
