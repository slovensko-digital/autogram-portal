require "test_helper"

class Users::RegistrationsControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers

  tests Users::RegistrationsController

  setup do
    @request.env["devise.mapping"] = Devise.mappings[:user]
    @user = users(:one)
    @user.update_columns(email: "admin@example.com", features: [ "admin" ])
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

  test "admin can update own features but admin feature remains enabled" do
    put :update, params: {
      user: {
        name: @user.name,
        api_token_public_key: @user.api_token_public_key,
        features: [ "api" ]
      }
    }

    assert_redirected_to edit_user_registration_path
    assert_equal [ "admin", "api" ], @user.reload.features.sort
  end

  test "non-admin feature updates are ignored" do
    @user.update_column(:features, [])

    put :update, params: {
      user: {
        name: @user.name,
        features: [ "api", "archivation" ]
      }
    }

    assert_redirected_to edit_user_registration_path
    assert_equal [], @user.reload.features
  end
end
