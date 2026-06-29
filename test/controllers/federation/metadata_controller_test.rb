require "test_helper"

class Federation::MetadataControllerTest < ActionDispatch::IntegrationTest
  test "shows federation metadata" do
    get "/.well-known/autogram-portal.json"

    assert_response :success
    assert_equal "http://www.example.com", response.parsed_body.fetch("issuer")
    assert_equal "Autogram Portal", response.parsed_body.fetch("portalName")
    assert_equal "http://www.example.com/api/federation/v1", response.parsed_body.fetch("federationApiBase")
    assert_equal true, response.parsed_body.fetch("capabilities").fetch("requestPreview")
  end
end
