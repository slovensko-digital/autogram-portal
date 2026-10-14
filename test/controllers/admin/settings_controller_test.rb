require "test_helper"

class Admin::SettingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update_columns(email: "admin@example.com", confirmed_at: Time.current, features: [ "admin" ])
  end

  test "admin settings link the administration sections and edit own features" do
    sign_in @admin

    get admin_settings_path

    assert_response :success
    assert_select "a[href=?]", admin_tenants_path
    assert_select "a[href=?]", admin_portal_instances_path
    assert_select "a[href=?]", "/admin/good_job"
    assert_select "input[type=checkbox][name='features[]']", count: User::AVAILABLE_FEATURES.size
    assert_select "input[type=checkbox][name='features[]'][value=admin][disabled][checked]"
  end

  test "admin settings are linked from the navigation, not the user settings" do
    sign_in @admin

    get edit_user_registration_path

    assert_response :success
    assert_select "a[href=?]", admin_settings_path, minimum: 1
    assert_select "a[href=?]", admin_tenants_path, count: 0
    assert_select "input[name='user[features][]']", count: 0
  end

  test "the navigation marks the admin settings as current on admin pages" do
    sign_in @admin

    get admin_tenants_path

    assert_select "a[href=?][aria-current=page]", admin_settings_path, minimum: 1
  end

  test "admin enables a feature and the admin feature stays enabled" do
    sign_in @admin

    patch admin_settings_path, params: { features: [ "federation", "unknown" ] }

    assert_redirected_to admin_settings_path
    assert_equal [ "admin", "federation" ], @admin.reload.features
  end

  test "admin disables all optional features" do
    @admin.update_column(:features, [ "admin", "federation" ])
    sign_in @admin

    patch admin_settings_path

    assert_redirected_to admin_settings_path
    assert_equal [ "admin" ], @admin.reload.features
  end

  test "non-admins have no admin settings" do
    @admin.update_column(:features, [])
    sign_in @admin

    get edit_user_registration_path
    assert_select "a[href=?]", admin_settings_path, count: 0

    get admin_settings_path
    assert_response :not_found

    patch admin_settings_path, params: { features: [ "federation" ] }
    assert_response :not_found
    assert_empty @admin.reload.features
  end
end
