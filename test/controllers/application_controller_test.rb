require "test_helper"

class ApplicationControllerTest < ActionController::TestCase
  class VerificationController < ApplicationController
    before_action :skip_authorization, only: [ :public_action ]

    def index
      authorize :dashboard if params[:authorize]
      policy_scope(Bundle) if params[:scope]
      head :ok
    end

    def show
      authorize :dashboard, :index? if params[:authorize]
      head :ok
    end

    def public_action
      head :ok
    end
  end

  tests VerificationController

  setup do
    @routes = ActionDispatch::Routing::RouteSet.new
    @routes.draw do
      get "index", to: "application_controller_test/verification#index"
      get "show", to: "application_controller_test/verification#show"
      get "public_action", to: "application_controller_test/verification#public_action"
    end

    user = users(:one)
    @controller.singleton_class.define_method(:current_user) { user }
    @controller.singleton_class.define_method(:user_signed_in?) { true }
  end

  test "authorization verification is inherited without a local hook" do
    assert_raises(Pundit::AuthorizationNotPerformedError) { get :show }
  end

  test "index authorization is required even when its relation is scoped" do
    assert_raises(Pundit::AuthorizationNotPerformedError) do
      get :index, params: { scope: "1" }
    end
  end

  test "index scope verification is inherited without a local hook" do
    assert_raises(Pundit::PolicyScopingNotPerformedError) do
      get :index, params: { authorize: "1" }
    end
  end

  test "authorized and scoped index passes verification" do
    get :index, params: { authorize: "1", scope: "1" }

    assert_response :success
  end

  test "non-index actions do not require a policy scope" do
    get :show, params: { authorize: "1" }

    assert_response :success
  end

  test "an explicit public action skip passes verification" do
    get :public_action

    assert_response :success
  end
end

class PublicAuthorizationExceptionsTest < ActionDispatch::IntegrationTest
  test "public index pages explicitly skip authorization and scoping" do
    get root_path
    assert_redirected_to about_index_path

    get about_index_path
    assert_response :success

    get docs_path
    assert_response :success
  end

  test "locale switching remains public" do
    post switch_locale_path, params: { locale: "en" }

    assert_redirected_to root_path
    assert_equal :en, session[:locale]
  end

  test "development tools configuration explicitly skips authorization" do
    get "/.well-known/appspecific/com.chrome.devtools.json"

    assert_response :success
    assert_equal "application/json", response.media_type
  end
end

class PublicSessionAuthorizationTest < ActionController::TestCase
  include Devise::Test::ControllerHelpers

  tests Users::SessionsController

  test "sign-in callbacks explicitly skip authorization" do
    @request.env["devise.mapping"] = Devise.mappings[:user]
    @controller.singleton_class.define_method(:new) { head :ok }

    get :new

    assert_response :success
  end
end
