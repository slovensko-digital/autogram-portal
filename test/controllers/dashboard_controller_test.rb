require "test_helper"

class DashboardControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers

  tests DashboardController

  setup do
    @user = users(:one)
    @user.update_column(:email, "dashboard@example.com")
    @user.current_tenant.update!(features: [ "archivation" ])
    @user.define_singleton_method(:accepted_current_policies?) { true }
    @user.define_singleton_method(:locale) { "en" }

    user = @user
    @controller.singleton_class.define_method(:authenticate_user!) { true }
    @controller.singleton_class.define_method(:current_user) { user }
    @controller.singleton_class.define_method(:user_signed_in?) { true }
  end

  test "index renders validation warning for records expiring within two months" do
    create_record(expires_at: 3.weeks.from_now)
    create_record(expires_at: 8.months.from_now)

    get :index

    assert_response :success
    assert_includes response.body, I18n.t("dashboard.index.validation_warning.title")
    assert_includes response.body, contract_validation_records_path(state: "expiring")
  end

  test "index hides archivation widgets when feature is disabled" do
    @user.current_tenant.update!(features: [])
    create_record(expires_at: 3.weeks.from_now)

    get :index

    assert_response :success
    assert_not_includes response.body, I18n.t("dashboard.index.validation_warning.title")
    assert_not_includes response.body, I18n.t("dashboard.index.quick_actions.validation_archive")
  end

  test "index counts pending invitations from trusted portals in awaiting signature total" do
    portal_instance = PortalInstance.create!(
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://partner.example/#{SecureRandom.hex(4)}",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem,
      allowed_email_domains: [ "example.com" ]
    )
    FederationRequestInvitation.create!(
      portal_instance: portal_instance,
      origin_recipient_uuid: SecureRandom.uuid,
      origin_bundle_uuid: SecureRandom.uuid,
      recipient_email: @user.email,
      payload: { "openUrl" => "https://origin.example/bundles/123/sign?recipient=abc" }
    )

    get :index

    assert_response :success
    assert_equal 1, @controller.instance_variable_get(:@awaiting_my_signature_count)
  end

  test "selector is hidden for a single tenant membership" do
    get :index

    assert_response :success
    assert_select "#tenant-selector-desktop", count: 0
    assert_select "#tenant-selector-mobile", count: 0
  end

  test "selector shows desktop and mobile dropdowns for two memberships" do
    organization = Tenant.create!(name: "Second org", kind: :organization)
    organization.tenant_users.create!(user: @user, role: :member)

    get :index

    assert_response :success
    assert_select "#tenant-selector-desktop", count: 1
    assert_select "#tenant-selector-mobile", count: 1
    assert_select "form[action='#{switch_tenant_path}'] input[name='tenant_id'][value='#{@user.current_tenant.id}']", count: 2
    assert_select "form[action='#{switch_tenant_path}'] input[name='tenant_id'][value='#{organization.id}']", count: 2
  end

  test "dashboard owner counts are isolated to the current tenant" do
    get :index

    assert_equal @user.current_tenant.bundles.count, @controller.instance_variable_get(:@bundles_count)
    assert_equal @user.current_tenant.contracts.standalone.count, @controller.instance_variable_get(:@contracts_count)
    assert_equal @user.current_tenant.bundles.order(created_at: :desc).limit(5),
                 @controller.instance_variable_get(:@recent_bundles)
  end

  private

  def create_record(tenant: @user.current_tenant, expires_at: nil)
    ContractValidationRecord.create!(
      tenant: tenant,
      source_contract_uuid: SecureRandom.uuid,
      source_version_number: 1,
      filename: "signed-contract.pdf",
      document_hash: Digest::SHA256.hexdigest(SecureRandom.hex(8)),
      signature_levels: [ "BASELINE_T" ],
      signatures_count: 1,
      expires_at: expires_at,
      validation_details: {}
    )
  end
end
