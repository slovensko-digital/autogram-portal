require "test_helper"

class GoogleSignInTest < ActionDispatch::IntegrationTest
  test "a failed Google sign-in offers to register or try again later" do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = :invalid_credentials

    get user_google_oauth2_omniauth_callback_path

    assert_redirected_to new_user_registration_url
    follow_redirect!
    assert_includes response.body, I18n.t("consents.google_sign_in_failed")
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:google_oauth2)
  end
end
