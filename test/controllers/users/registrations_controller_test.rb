require "test_helper"

class Users::RegistrationsControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers

  tests Users::RegistrationsController

  setup do
    @request.env["devise.mapping"] = Devise.mappings[:user]
    @user = users(:one)
    @user.update_column(:email, "user@example.com")
    @user.define_singleton_method(:accepted_current_policies?) { true }
    @user.define_singleton_method(:locale) { "en" }

    user = @user
    @controller.singleton_class.define_method(:authenticate_user!) { true }
    @controller.singleton_class.define_method(:authenticate_scope!) { true }
    @controller.singleton_class.define_method(:current_user) { user }
    @controller.singleton_class.define_method(:user_signed_in?) { true }
    @controller.singleton_class.define_method(:current_user_session) { nil }
    @controller.singleton_class.define_method(:resource) { user }
    @controller.singleton_class.define_method(:resource_name) { :user }
  end

  test "updates the user name" do
    put :update, params: { user: { name: "New Name" } }

    assert_redirected_to edit_user_registration_path
    assert_equal "New Name", @user.reload.name
  end

  test "edit renders the user profile form" do
    get :edit

    assert_response :success
    assert_select "input[name='user[name]']"
  end

  test "edit renders tenant settings section for admin membership" do
    get :edit

    assert_response :success
    assert_select "textarea[name='tenant[api_token_public_key]']"
    assert_select "input[name='tenant[features][]'][value='api']"
  end
end
