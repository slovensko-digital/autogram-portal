class ApiController < ActionController::API
  include Pundit::Authorization

  before_action :authenticate_tenant!
  before_action :set_json_format
  after_action :verify_authorized

  rescue_from JWT::DecodeError do |error|
    render_unauthorized("API token")
  end

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :render_bad_request
  rescue_from Pundit::NotAuthorizedError, with: :render_not_found
  rescue_from PlanLimits::Exceeded, with: :render_limit_exceeded

  DecodedDocument = Data.define(:params, :content)

  def current_tenant
    @current_tenant
  end

  private

  def pundit_user
    AuthorizationContext::TenantApi.new(tenant: current_tenant)
  end

  def authenticate_tenant!
    @current_tenant = ApiEnvironment.token_authenticator.verify_token(authenticity_token)
  rescue JWT::VerificationError, JWT::InvalidSubError => error
    render_unauthorized(error.message)
  end

  def authenticity_token
    (ActionController::HttpAuthentication::Token.token_and_options(request)&.first&.gsub("Bearer ", "") || params[:token])&.squish.presence
  end

  def decode_documents(documents)
    Array(documents).map do |document|
      content = document[:content].presence
      content = Base64.decode64(content) if content && document[:contentType].to_s.include?("base64")
      DecodedDocument.new(params: document, content: content)
    end
  end

  # Checks all contracts of a request (each an array of DecodedDocument) against the document size
  # and plan limits before anything is uploaded, so a rejected request leaves no blobs behind.
  def ensure_documents_fit_limits!(contracts_documents)
    sizes = contracts_documents.map { |documents| documents.sum { |document| document.content.to_s.bytesize } }

    max_document_bytes = PlanLimits.max_document_bytes
    if max_document_bytes && sizes.max.to_i > max_document_bytes
      raise PlanLimits::Exceeded.new(limit: :document_size, max: max_document_bytes, used: sizes.max)
    end

    current_tenant.ensure_within_limit!(:stored_documents, contracts_documents.size)
    current_tenant.ensure_within_limit!(:storage, sizes.sum)
  end

  def document_attributes(document)
    document_params = document.params
    attributes = {
      xdc_parameters_attributes: document_params[:xdcParameters]&.transform_keys(&:underscore) || {}
    }

    attributes[:url] = document_params[:url] if document_params[:url].present?
    attributes[:remote_hash] = document_params[:hash] if document_params[:hash].present?
    attributes[:uuid] = document_params[:id] if document_params[:id].present?

    if document.content
      attributes[:blob] = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(document.content),
        filename: document_params[:filename],
        content_type: document_params[:contentType].to_s.split(";").first&.strip
      )
    end

    attributes
  end

  def render_limit_exceeded(error)
    render status: :unprocessable_entity, json: { errors: [ error.message ], code: "limit_exceeded", limit: error.limit.to_s }
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

  def set_json_format
    request.format = :json
  end
end
