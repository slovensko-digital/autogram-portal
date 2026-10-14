require "test_helper"
require_relative "../support/staging_instance_helper"

class StagingInstanceTest < ActiveSupport::TestCase
  include StagingInstanceHelper

  test "an instance without PRODUCTION_URL is not a test one and lets anyone sign up" do
    ENV.delete("PRODUCTION_URL")

    assert_not StagingInstance.active?
    assert_nil StagingInstance.production_host
    assert StagingInstance.signup_allowed?("someone@example.com")
  end

  test "a test instance links to production" do
    assert StagingInstance.active?
    assert_equal "agp.slovensko.digital", StagingInstance.production_host
    assert_equal "https://agp.slovensko.digital/users/sign_up", StagingInstance.production_url_for("/users/sign_up")
  end

  test "a test instance lets only slovensko.digital and its subdomains sign up by default" do
    assert StagingInstance.signup_allowed?(" Tester@Slovensko.Digital ")
    assert StagingInstance.signup_allowed?("tester@dev.slovensko.digital")
    assert_not StagingInstance.signup_allowed?("tester@evilslovensko.digital")
    assert_not StagingInstance.signup_allowed?("slovensko.digital@example.com")
    assert_not StagingInstance.signup_allowed?("")
    assert_not StagingInstance.signup_allowed?(nil)
    assert_equal "@slovensko.digital", StagingInstance.signup_allowed_addresses
  end

  test "allowed sign-up domains come from SIGNUP_ALLOWED_DOMAINS" do
    ENV["SIGNUP_ALLOWED_DOMAINS"] = " Example.com, ,firma.sk"

    assert_equal %w[example.com firma.sk], StagingInstance.signup_allowed_domains
    assert_equal "@example.com, @firma.sk", StagingInstance.signup_allowed_addresses
    assert StagingInstance.signup_allowed?("someone@firma.sk")
    assert_not StagingInstance.signup_allowed?("tester@slovensko.digital")
  end
end
