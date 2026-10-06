require "test_helper"

class ConsentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    # users(:two) has not accepted the current policies.
    @user = users(:two)
    @user.update_columns(email: "consent@example.com", confirmed_at: Time.current)
    @pro_tenant = tenants(:one)
    @pro_tenant.update!(plan: :pro)
    @pro_tenant.memberships.create!(user: @user)
  end

  test "basic tenant requires consent with the current policies" do
    sign_in @user
    post tenant_selection_path(tenant_id: tenants(:two).id)
    assert_redirected_to dashboard_path

    get dashboard_path
    assert_redirected_to new_consent_path

    post consent_path, params: { agree_to_policies: "1" }
    assert_redirected_to root_path
    assert @user.reload.accepted_current_policies?

    get dashboard_path
    assert_response :success
  end

  test "pro tenant members are not asked for consent" do
    sign_in @user

    get tenant_selection_path
    assert_response :success

    post tenant_selection_path(tenant_id: @pro_tenant.id)
    assert_redirected_to dashboard_path

    get dashboard_path
    assert_response :success
    assert_not @user.reload.accepted_current_policies?
  end

  test "locale can be switched before a tenant is chosen" do
    sign_in @user

    post switch_locale_path(locale: "en"), headers: { "HTTP_REFERER" => tenant_selection_url }
    assert_redirected_to tenant_selection_url
  end
end
