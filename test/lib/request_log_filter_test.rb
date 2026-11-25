require "test_helper"
require "rack/mock"

# Request logs hold no documents, no data of people and no signing links
# (config/initializers/filter_parameter_logging.rb).
class RequestLogFilterTest < ActiveSupport::TestCase
  PRIVATE_VALUES = %w[zmluva-novak JVBERi0 c2lnbmVk jan.novak Novak +421900123456 048855 tajny-token Dobry.den eyJfcmFpbHM hladany].freeze

  test "parameters of API requests are logged without documents and recipients" do
    logged = filter(
      "id" => "b1",
      "contracts" => [ { "id" => "c1", "allowedMethods" => [ "qes" ], "documents" => [ { "filename" => "zmluva-novak.pdf", "content" => "JVBERi0xLjQ=", "contentType" => "application/pdf;base64" } ] } ],
      "recipients" => [ { "email" => "jan.novak@example.com", "name" => "Jan Novak", "phone" => "+421900123456" } ],
      "invitation" => { "authorName" => "Jan Novak", "note" => "Dobry.den", "openUrl" => "https://origin.example/bundles/1/sign?recipient=tajny-token" }
    )

    assert_no_private_values logged
    assert_equal "b1", logged["id"]
    assert_equal "c1", logged.dig("contracts", 0, "id")
    assert_equal [ "qes" ], logged.dig("contracts", 0, "allowedMethods")
  end

  test "parameters of web requests are logged without files, signatures, codes and names" do
    upload = Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4"), "application/pdf", original_filename: "zmluva-novak.pdf")
    logged = filter(
      "contract" => { "documents_attributes" => [ { "blob" => upload } ] }, "file" => upload,
      "signed_document" => "c2lnbmVk", "signed_id" => "eyJfcmFpbHMiOnt9fQ==--38c2", "filename" => "zmluva-novak.pdf",
      "stamp" => { "custom_text" => "Jan Novak", "content_mode" => "text", "image" => "data:image/png;base64,JVBERi0", "drawing_data" => "JVBERi0" },
      "verification_code" => "048855", "mobile_phone" => "+421900123456", "q" => "hladany", "recipient" => "tajny-token",
      "recipient_uuid" => "r-1", "document_uuid" => "d-1", "contract_id" => "c-1", "locale" => "sk"
    )

    assert_no_private_values logged
    assert_equal({ "recipient_uuid" => "r-1", "document_uuid" => "d-1", "contract_id" => "c-1", "locale" => "sk" }, logged.slice("recipient_uuid", "document_uuid", "contract_id", "locale"))
    assert_equal "text", logged.dig("stamp", "content_mode")
  end

  test "photos of signed pages and the reason a scan is returned are not logged" do
    photo = Rack::Test::UploadedFile.new(StringIO.new("JVBERi0"), "image/jpeg", original_filename: "zmluva-novak.jpg")
    logged = filter(
      "files" => [ photo, photo ], "reason" => "Dobry.den", "paper_signature" => { "return_reason" => "Dobry.den" },
      "recipient" => "tajny-token", "contract_id" => "c-1", "id" => "7", "position" => "2"
    )

    assert_no_private_values logged
    assert_equal({ "contract_id" => "c-1", "id" => "7", "position" => "2" }, logged.slice("contract_id", "id", "position"))
  end

  test "the signing link of a recipient is logged without its key" do
    env = Rack::MockRequest.env_for("/bundles/b-1?recipient=tajny-token&locale=sk", "action_dispatch.parameter_filter" => Rails.application.config.filter_parameters)

    assert_equal "/bundles/b-1?recipient=[FILTERED]&locale=sk", ActionDispatch::Request.new(env).filtered_path
  end

  test "the phone link to a paper signature is logged without its token" do
    env = Rack::MockRequest.env_for("/contracts/c-1/paper_signature?token=tajny-token", "action_dispatch.parameter_filter" => Rails.application.config.filter_parameters)
    request = ActionDispatch::Request.new(env)
    response = ActionDispatch::Response.new
    response.request = request
    response.location = "http://www.example.com/contracts/c-1/paper_signature/pages/7?token=tajny-token"

    assert_equal "/contracts/c-1/paper_signature?token=[FILTERED]", request.filtered_path
    assert_equal "http://www.example.com/contracts/c-1/paper_signature/pages/7?token=[FILTERED]", response.filtered_location
  end

  private

  def filter(parameters)
    ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(parameters)
  end

  def assert_no_private_values(logged)
    assert_empty PRIVATE_VALUES.select { logged.inspect.include?(it) }
  end
end
