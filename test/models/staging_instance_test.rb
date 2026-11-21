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

  test "a test instance lets anyone sign up by default" do
    assert_not StagingInstance.signup_restricted?
    assert_empty StagingInstance.signup_allowed_domains
    assert StagingInstance.signup_allowed?("someone@example.com")
  end

  test "SIGNUP_ALLOWED_DOMAINS restricts sign-up to the domains and their subdomains" do
    ENV["SIGNUP_ALLOWED_DOMAINS"] = " Slovensko.digital, ,firma.sk"

    assert StagingInstance.signup_restricted?
    assert_equal %w[slovensko.digital firma.sk], StagingInstance.signup_allowed_domains
    assert_equal "@slovensko.digital, @firma.sk", StagingInstance.signup_allowed_addresses
    assert StagingInstance.signup_allowed?(" Tester@Slovensko.Digital ")
    assert StagingInstance.signup_allowed?("tester@dev.slovensko.digital")
    assert StagingInstance.signup_allowed?("someone@firma.sk")
    assert_not StagingInstance.signup_allowed?("tester@evilslovensko.digital")
    assert_not StagingInstance.signup_allowed?("slovensko.digital@example.com")
    assert_not StagingInstance.signup_allowed?("")
    assert_not StagingInstance.signup_allowed?(nil)
  end

  test "SIGNUP_ALLOWED_DOMAINS does not restrict production" do
    ENV.delete("PRODUCTION_URL")
    ENV["SIGNUP_ALLOWED_DOMAINS"] = "slovensko.digital"

    assert_not StagingInstance.signup_restricted?
    assert StagingInstance.signup_allowed?("someone@example.com")
  end

  test "a test instance redirects mail of tenants without real emails" do
    tenant = tenants(:one)
    assert StagingInstance.redirect_mail_for?(tenant)
    assert StagingInstance.redirect_mail_for?(nil)

    tenant.update!(features: [ "staging_real_mail" ])
    assert_not StagingInstance.redirect_mail_for?(tenant)

    tenant.update!(features: [])
    ENV.delete("PRODUCTION_URL")
    assert_not StagingInstance.redirect_mail_for?(tenant)
  end
end
