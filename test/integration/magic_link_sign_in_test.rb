require "test_helper"

class MagicLinkSignInTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update_columns(email: "magic@example.com", confirmed_at: Time.current)
  end

  test "magic link with remember me signs in and sets the remember cookie" do
    get user_magic_link_path(user: { email: @user.email, token: @user.encode_passwordless_token, remember_me: "1" })

    assert_response :redirect
    assert cookies["remember_user_token"].present?
    assert @user.reload.remember_token.present?

    get dashboard_path
    assert_response :success
  end

  test "signing out forgets the remember token" do
    get user_magic_link_path(user: { email: @user.email, token: @user.encode_passwordless_token, remember_me: "1" })

    delete destroy_user_session_path

    assert_nil @user.reload.remember_token
  end
end
