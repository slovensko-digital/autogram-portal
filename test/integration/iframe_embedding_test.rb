require "test_helper"

class IframeEmbeddingTest < ActionDispatch::IntegrationTest
  setup do
    @recipient = bundles(:one).recipients.create!(email: "recipient-#{SecureRandom.hex(6)}@example.com", locale: "en")
  end

  test "embedded signing page can be framed by any https origin" do
    get sign_bundle_path(@recipient.bundle, recipient: @recipient.uuid, iframe: "true")

    assert_response :success
    assert_nil response.headers["X-Frame-Options"]
    assert_match(/frame-ancestors 'self' http:\/\/localhost:\* https:(;|\z)/, response.headers["Content-Security-Policy"])
  end

  test "signing page outside iframe can be framed only by the portal" do
    get sign_bundle_path(@recipient.bundle, recipient: @recipient.uuid)

    assert_response :success
    assert_match(/frame-ancestors 'self' http:\/\/localhost:\*(;|\z)/, response.headers["Content-Security-Policy"])
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
  end

  test "files from the disk service can be framed by any https origin" do
    ActiveStorage::Current.url_options = { host: "www.example.com" }
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("%PDF-1.4"), filename: "document.pdf", content_type: "application/pdf")

    get rails_blob_path(blob, disposition: "inline")
    follow_redirect!

    assert_response :success
    assert_nil response.headers["X-Frame-Options"]
    assert_match(/frame-ancestors 'self' http:\/\/localhost:\* https:(;|\z)/, response.headers["Content-Security-Policy"])
  ensure
    ActiveStorage::Current.reset
  end
end
