require "test_helper"

class Admin::TenantsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update_columns(email: "admin@example.com", confirmed_at: Time.current, features: [ "admin" ])
    @tenant = tenants(:two)
  end

  test "admin changes plan and features of a tenant" do
    sign_in @admin

    patch admin_tenant_path(@tenant), params: { tenant: { name: "Firma s.r.o.", plan: "pro", features: [ "", "api", "archivation" ] } }

    assert_redirected_to admin_tenants_path
    @tenant.reload
    assert @tenant.pro?
    assert_equal "Firma s.r.o.", @tenant.name
    assert_equal [ "api", "archivation" ], @tenant.features
  end

  test "admin can clear all features" do
    @tenant.update!(features: [ "api" ])
    sign_in @admin

    patch admin_tenant_path(@tenant), params: { tenant: { features: [ "" ] } }

    assert_empty @tenant.reload.features
  end

  test "admin adds an existing user to a pro tenant" do
    @tenant.update!(plan: :pro)
    sign_in @admin

    post add_member_admin_tenant_path(@tenant), params: { email: @admin.email, role: "owner" }

    assert_redirected_to edit_admin_tenant_path(@tenant)
    assert @tenant.owner?(@admin)
  end

  test "admin edit renders plan, features and members" do
    sign_in @admin

    get edit_admin_tenant_path(@tenant)

    assert_response :success
    assert_select "select[name='tenant[plan]']"
    assert_select "input[type=checkbox][name='tenant[features][]']", count: Tenant::AVAILABLE_FEATURES.size
  end

  test "admin creates an organization for a new customer email" do
    sign_in @admin

    assert_difference -> { Tenant.count } => 1, -> { User.count } => 1 do
      assert_emails 1 do
        post admin_tenants_path, params: { owner_email: "Owner@Firma-ABC.sk", tenant: { name: "Firma ABC", plan: "pro", features: [ "", "api" ] } }
      end
    end

    tenant = Tenant.find_by!(name: "Firma ABC")
    owner = User.find_by!(email: "owner@firma-abc.sk")
    assert_redirected_to edit_admin_tenant_path(tenant)
    assert tenant.pro?
    assert_equal [ "api" ], tenant.features
    assert tenant.owner?(owner)
    assert_equal [ tenant ], owner.tenants.to_a
    assert_not owner.confirmed?
  end

  test "creating an organization for an existing user removes their unused personal tenant" do
    customer = User.create!(email: "customer-#{SecureRandom.hex(4)}@example.com")
    personal = customer.tenants.sole
    sign_in @admin

    post admin_tenants_path, params: { owner_email: customer.email, tenant: { name: "Firma ABC", plan: "pro" } }

    tenant = Tenant.find_by!(name: "Firma ABC")
    assert_not Tenant.exists?(personal.id)
    assert_equal [ tenant ], customer.reload.tenants.to_a
  end

  test "creating an organization requires an owner email" do
    sign_in @admin

    assert_no_difference -> { Tenant.count } do
      post admin_tenants_path, params: { owner_email: "", tenant: { name: "Firma ABC", plan: "pro" } }
    end

    assert_response :unprocessable_entity
  end

  test "admin new form asks for the owner email" do
    sign_in @admin

    get new_admin_tenant_path

    assert_response :success
    assert_select "input[name='owner_email']"
  end

  test "admin index lists tenants" do
    sign_in @admin

    get admin_tenants_path

    assert_response :success
    assert_includes response.body, @tenant.name
  end

  test "non-admins cannot manage tenants" do
    @admin.update_column(:features, [])
    sign_in @admin

    get admin_tenants_path

    assert_response :not_found
  end
end
