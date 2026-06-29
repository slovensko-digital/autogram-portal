require "test_helper"

class Federation::RequestsControllerTest < ActionController::TestCase
  tests Federation::RequestsController

  setup do
    @user = users(:one)
    @user.update_column(:email, "user@example.com")
    @user.define_singleton_method(:accepted_current_policies?) { true }
    @user.define_singleton_method(:locale) { "en" }

    @controller.singleton_class.define_method(:current_user) { nil }
    @controller.singleton_class.define_method(:user_signed_in?) { false }
  end

  test "show renders preview details for a pasted request URL" do
    broker = Object.new
    broker.define_singleton_method(:preview) do |url:|
      FederationRequestBroker::Preview.new(
        portal_instance: PortalInstance.new(name: "Partner Portal"),
        request: {
          "authorName" => "Sender <sender@example.com>",
          "contracts" => [ { "displayName" => "Contract 1" } ],
          "note" => "Please sign"
        }
      )
    end

    @controller.singleton_class.define_method(:federation_request_broker) { broker }

    get :show, params: { url: "https://partner.example/bundles/bundle-1/sign?recipient=recipient-1" }

    assert_response :success
    assert_includes response.body, "Partner Portal"
    assert_includes response.body, "Contract 1"
    assert_includes response.body, "Please sign"
  end

  test "claim redirects to broker sign url for signed in users" do
    broker = Object.new
    broker.define_singleton_method(:claim) do |url:, claimant:|
      "https://partner.example/bundles/bundle-1/sign?grant=abc"
    end

    user = @user
    @controller.singleton_class.define_method(:authenticate_user!) { true }
    @controller.singleton_class.define_method(:current_user) { user }
    @controller.singleton_class.define_method(:user_signed_in?) { true }

    @controller.singleton_class.define_method(:federation_request_broker) { broker }

    post :claim, params: { url: "https://partner.example/bundles/bundle-1/sign?recipient=recipient-1" }

    assert_redirected_to "https://partner.example/bundles/bundle-1/sign?grant=abc"
  end
end
