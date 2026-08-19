require "test_helper"

class TenantsControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers

  tests TenantsController

  setup do
    @user = users(:one)
    @user.define_singleton_method(:accepted_current_policies?) { true }
    user = @user
    @controller.singleton_class.define_method(:authenticate_user!) { true }
    @controller.singleton_class.define_method(:current_user) { user }
    @controller.singleton_class.define_method(:user_signed_in?) { true }
  end

  test "switches to a member tenant and redirects to dashboard" do
    organization = create_organization_for(@user)

    post :switch, params: { tenant_id: organization.id }

    assert_redirected_to dashboard_path
    assert_equal organization, @user.reload.current_tenant
  end

  test "rejects a tenant the user does not belong to" do
    post :switch, params: { tenant_id: tenants(:two).id }

    assert_response :not_found
    assert_equal tenants(:one), @user.reload.current_tenant
  end

  test "switch always redirects to dashboard regardless of referer" do
    organization = create_organization_for(@user)
    @request.headers["HTTP_REFERER"] = "https://malicious.example/redirect"

    post :switch, params: { tenant_id: organization.id }

    assert_redirected_to dashboard_path
  end

  test "current tenant repairs an invalid persisted selection deterministically" do
    organization = create_organization_for(@user)
    @user.update_column(:current_tenant_id, tenants(:two).id)

    selected = @controller.current_tenant

    assert_equal [ tenants(:one), organization ].min_by(&:id), selected
    assert_equal selected, @user.reload.current_tenant
  end

  test "admin membership can update tenant settings" do
    organization = create_organization_for(@user, role: :admin)
    @user.update_column(:current_tenant_id, organization.id)

    patch :update_settings, params: {
      tenant: {
        api_token_public_key: "new-public-key",
        features: [ "api" ]
      }
    }

    assert_redirected_to edit_user_registration_path
    assert_equal "new-public-key", organization.reload.api_token_public_key
    assert_equal [ "api" ], organization.reload.features
  end

  test "member membership cannot update tenant settings" do
    organization = create_organization_for(@user, role: :member)
    @user.update_column(:current_tenant_id, organization.id)

    patch :update_settings, params: {
      tenant: { features: [ "api" ] }
    }

    assert_response :forbidden
    assert_empty organization.reload.features
  end

  test "global admin user with member role cannot update tenant settings" do
    @user.update!(admin: true)
    organization = create_organization_for(@user, role: :member)
    @user.update_column(:current_tenant_id, organization.id)

    patch :update_settings, params: {
      tenant: { features: [ "api" ] }
    }

    assert_response :forbidden
  end

  private

  def create_organization_for(user, role: :member)
    Tenant.create!(name: "Shared organization", kind: :organization).tap do |tenant|
      tenant.tenant_users.create!(user: user, role: role)
    end
  end
end
