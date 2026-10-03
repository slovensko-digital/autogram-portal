module ErrorPagesHelper
  ERROR_PAGE_KEYS = {
    400 => "bad_request",
    403 => "forbidden",
    404 => "not_found",
    422 => "unprocessable",
    500 => "internal_server_error"
  }.freeze

  def error_page_key(status)
    ERROR_PAGE_KEYS.fetch(status, "generic")
  end
end
