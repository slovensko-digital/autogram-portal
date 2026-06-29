require "test_helper"
require "openssl"

class Admin::PortalInstancesControllerTest < ActionController::TestCase
  tests Admin::PortalInstancesController

  setup do
    @user = users(:one)
    @user.update_column(:email, "admin@example.com")
    @user.update_column(:features, [ "admin" ])
    @user.define_singleton_method(:accepted_current_policies?) { true }
    @user.define_singleton_method(:locale) { "en" }

    user = @user
    @controller.singleton_class.define_method(:authenticate_user!) { true }
    @controller.singleton_class.define_method(:current_user) { user }
    @controller.singleton_class.define_method(:user_signed_in?) { true }
  end

  test "index lists portal instances for admins" do
    portal_instance = create_portal_instance(name: "Partner Portal")

    get :index

    assert_response :success
    assert_includes response.body, "Partner Portal"
    assert_includes response.body, portal_instance.base_url
  end

  test "create persists a portal instance" do
    assert_difference("PortalInstance.count", 1) do
      post :create, params: {
        portal_instance: {
          name: "Portal B",
          base_url: "https://example.com",
          issuer: "https://portal-b.example.com",
          public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem,
          status: "verified",
          allowed_email_domains: [ "portal-b.example.com" ]
        }
      }
    end

    assert_redirected_to admin_portal_instances_path
    assert_equal "Portal B", PortalInstance.order(:id).last.name
  end

  test "revoke marks a portal as revoked" do
    portal_instance = create_portal_instance(status: "verified")

    post :revoke, params: { id: portal_instance.uuid }

    assert_redirected_to admin_portal_instances_path
    assert_equal "revoked", portal_instance.reload.status
  end

  test "non-admin users are forbidden" do
    @user.update_column(:features, [])

    get :index

    assert_response :forbidden
  end

  private

  def create_portal_instance(**attributes)
    PortalInstance.create!({
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://issuer.example.com/#{SecureRandom.hex(4)}",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem,
      allowed_email_domains: [ "partner.example" ]
    }.merge(attributes))
  end
end
