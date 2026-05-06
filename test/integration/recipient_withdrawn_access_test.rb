require "test_helper"

class RecipientWithdrawnAccessTest < ActionDispatch::IntegrationTest
  test "withdrawn recipient link shows withdrawn message instead of 404" do
    recipient = bundles(:one).recipients.create!(
      email: "recipient-#{SecureRandom.hex(6)}@example.com",
      locale: "en"
    )
    recipient.update!(notification_status: :notified)
    recipient.withdraw!

    get sign_bundle_path(recipient.bundle, recipient: recipient.uuid)

    assert_response :gone
    assert_includes response.body, I18n.t("bundles.sign.withdrawn_info_title")
    assert_includes response.body, I18n.t("bundles.sign.withdrawn_info_message")
  end
end
