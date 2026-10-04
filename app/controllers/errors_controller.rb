# Error pages for exceptions Rails handles itself (config.exceptions_app).
# Inherits ActionController::Base on purpose: no authentication, tenant, policy or database access,
# so the page still renders when the error comes from one of those layers.
class ErrorsController < ActionController::Base
  skip_forgery_protection

  layout "errors"

  def show
    status = request.path_info.delete_prefix("/").to_i
    status = 500 unless status.between?(400, 599)

    I18n.with_locale(error_page_locale) do
      respond_to do |format|
        format.html { render :show, status: status, locals: { status: status } }
        format.json { render json: { error: Rack::Utils::HTTP_STATUS_CODES[status] }, status: status }
        format.any { head status }
      end
    end
  end

  private

  # Params are not read: a malformed request (400) fails while parsing them.
  def error_page_locale
    locale = (session[:locale] || cookies[:locale]).to_s
    I18n.available_locales.map(&:to_s).include?(locale) ? locale : I18n.default_locale
  rescue StandardError
    I18n.default_locale
  end
end
