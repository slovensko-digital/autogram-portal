require "test_helper"
require "jwt"
require_relative "../support/staging_instance_helper"

# On a test instance every organization may try the API for free, Basic ones included.
class StagingApiTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StagingInstanceHelper

  setup do
    @owner = users(:one)
    @owner.update_columns(email: "owner@example.com", confirmed_at: Time.current)
    @tenant = tenants(:one)
  end

  test "owner of a basic tenant sets the api key and calls the api" do
    key = OpenSSL::PKey::RSA.generate(2048)
    sign_in @owner

    get edit_user_registration_path
    assert_response :success
    assert_select "#api-staging-notice a[href=?]", PRODUCTION_URL
    assert_select "#api-staging-notice a[href=?]", docs_path(anchor: "integration")
    assert_select "textarea[name='tenant[api_token_public_key]']:not([disabled])"
    assert_not_includes response.body, I18n.t("tenants.settings.api_pro_only_title")

    patch tenant_path, params: { tenant: { api_token_public_key: key.public_to_pem } }
    assert_redirected_to edit_user_registration_path(anchor: "organization")
    assert_equal key.public_to_pem, @tenant.reload.api_token_public_key
    assert @tenant.basic?
    assert_empty @tenant.features

    get "/api/v1/hello_auth", headers: bearer_headers_for(@tenant, key)
    assert_response :success
    assert_equal "Hello, #{@tenant.id}!", response.parsed_body["message"]
  end

  test "the api still requires the tenant's own key" do
    @tenant.update!(api_token_public_key: OpenSSL::PKey::RSA.generate(2048).public_to_pem)

    get "/api/v1/hello_auth", headers: bearer_headers_for(@tenant, OpenSSL::PKey::RSA.generate(2048))
    assert_response :unauthorized

    get "/api/v1/hello_auth", headers: bearer_headers_for(tenants(:two), OpenSSL::PKey::RSA.generate(2048))
    assert_response :unauthorized
  end

  test "member of an organization cannot change its api key" do
    colleague = users(:two)
    colleague.update_columns(email: "colleague@example.com", confirmed_at: Time.current)
    @tenant.update!(plan: :pro)
    @tenant.memberships.create!(user: colleague)
    sign_in colleague
    post tenant_selection_path(tenant_id: @tenant.id)

    get edit_user_registration_path
    assert_select "textarea[name='tenant[api_token_public_key]'][disabled]"

    patch tenant_path, params: { tenant: { api_token_public_key: OpenSSL::PKey::RSA.generate(2048).public_to_pem } }
    assert_equal I18n.t("tenants.alerts.owner_required"), flash[:alert]
    assert_nil @tenant.reload.api_token_public_key
  end

  test "user guide and administration say the api is free here" do
    get docs_path
    assert_select "#api-staging-note", text: I18n.t("docs.index.integration.staging_note")

    @owner.update_columns(features: [ "admin" ])
    sign_in @owner
    get edit_admin_tenant_path(@tenant)
    assert_response :success
    assert_includes response.body, I18n.t("admin.tenants.form.api_on_staging")
  end

  private

  def bearer_headers_for(tenant, key)
    token = JWT.encode({ sub: tenant.id.to_s, exp: 10.minutes.from_now.to_i, jti: SecureRandom.hex(16) }, key, "RS256")

    { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
  end
end
