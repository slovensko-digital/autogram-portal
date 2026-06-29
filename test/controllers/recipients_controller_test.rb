require "test_helper"
require "openssl"

class RecipientsControllerTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers

  tests RecipientsController

  setup do
    @user = users(:one)
    @user.update_column(:email, "owner@example.com")
    @user.define_singleton_method(:accepted_current_policies?) { true }
    @user.define_singleton_method(:locale) { "en" }

    user = @user
    @controller.singleton_class.define_method(:authenticate_user!) { true }
    @controller.singleton_class.define_method(:current_user) { user }
    @controller.singleton_class.define_method(:user_signed_in?) { true }
  end

  test "index renders trusted portal selection" do
    portal_instance = create_portal_instance(name: "Partner Portal")

    get :index, params: { bundle_id: bundles(:one).uuid }

    assert_response :success
    assert_select "select[name='recipient[portal_instance_uuid]']"
    assert_select "option[value='#{portal_instance.uuid}']", text: "Partner Portal"
  end

  test "create stores a federated recipient via portal selection" do
    portal_instance = create_portal_instance

    post :create, params: {
      bundle_id: bundles(:one).uuid,
      recipient: {
        email: "recipient@partner.example",
        portal_instance_uuid: portal_instance.uuid
      }
    }

    assert_response :success

    recipient = bundles(:one).recipients.find_by!(email: "recipient@partner.example")
    assert_equal portal_instance, recipient.portal_instance
    assert recipient.federated_recipient?
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
