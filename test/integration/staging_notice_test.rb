require "test_helper"
require_relative "../support/staging_instance_helper"

class StagingNoticeTest < ActionDispatch::IntegrationTest
  include StagingInstanceHelper

  test "pages of a test instance say so and link to production" do
    get about_index_path

    assert_response :success
    assert_select "title", text: /\A\[TEST\] /
    assert_select "#staging-notice[aria-label=?]", I18n.t("layouts.staging_notice.label") do
      assert_select "a[href=?]", PRODUCTION_URL, text: "agp.slovensko.digital"
    end
  end

  test "error pages of a test instance show the notice too" do
    get "/404"

    assert_select "title", text: /\A\[TEST\] /
    assert_select "#staging-notice a[href=?]", PRODUCTION_URL
  end

  test "embedded pages show no notice" do
    recipient = bundles(:one).recipients.create!(email: "recipient-#{SecureRandom.hex(6)}@example.com", locale: "en")

    get sign_bundle_path(recipient.bundle, recipient: recipient.uuid, iframe: "true")

    assert_response :success
    assert_select "#staging-notice", count: 0
    assert_select "title", text: /\[TEST\]/, count: 0
  end

  test "production pages show no notice" do
    ENV.delete("PRODUCTION_URL")

    get about_index_path

    assert_select "#staging-notice", count: 0
    assert_select "title", text: /\[TEST\]/, count: 0
  end

  test "a test instance lets only allowed domains sign up and marks their emails" do
    assert_no_difference -> { User.count } do
      post user_registration_path, params: { user: { email: "someone@example.com", agree_to_policies: "1" } }
    end
    assert_redirected_to new_user_registration_path
    assert_equal I18n.t("devise.registrations.staging_signup_domain", addresses: "@slovensko.digital"), flash[:alert]

    assert_difference -> { User.count } do
      post user_registration_path, params: { user: { email: "tester-#{SecureRandom.hex(4)}@slovensko.digital", agree_to_policies: "1" } }
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal "[TEST] #{I18n.t("devise.mailer.confirmation_instructions.subject")}", mail.subject
    assert_includes mail.html_part.body.decoded, %(href="#{PRODUCTION_URL}")
    assert_includes mail.text_part.body.decoded, I18n.t("layouts.mailer.staging_notice", url: PRODUCTION_URL)
  end

  test "production lets any domain sign up" do
    ENV.delete("PRODUCTION_URL")

    assert_difference -> { User.count } do
      post user_registration_path, params: { user: { email: "someone-#{SecureRandom.hex(4)}@example.com", agree_to_policies: "1" } }
    end

    assert_not ActionMailer::Base.deliveries.last.subject.start_with?("[TEST]")
  end

  test "application mails of a test instance are marked too" do
    tenant = tenants(:one)
    tenant.update!(plan: :pro)
    user = User.find_or_invite!("invited-#{SecureRandom.hex(4)}@example.com", locale: "en")
    membership = tenant.memberships.create!(user: user)

    mail = TenantMailer.with(membership: membership).invitation

    assert_equal "[TEST] #{I18n.t("tenant_mailer.invitation.subject", tenant: tenant.name, locale: :en)}", mail.subject
    assert_includes mail.html_part.body.decoded, %(href="#{PRODUCTION_URL}")
    assert_includes mail.text_part.body.decoded, I18n.t("layouts.mailer.staging_notice", url: PRODUCTION_URL, locale: :en)
  end

  test "the sign-up page of a test instance links to sign-up in production" do
    get new_user_registration_path

    assert_select "a[href=?]", "#{PRODUCTION_URL}#{new_user_registration_path}"
  end

  test "Google sign-in on a test instance creates no users outside allowed domains" do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = google_auth("someone@example.com")
    get user_google_oauth2_omniauth_callback_path

    assert_redirected_to new_user_registration_url
    assert_equal I18n.t("devise.registrations.staging_signup_domain", addresses: "@slovensko.digital"), flash[:alert]

    OmniAuth.config.mock_auth[:google_oauth2] = google_auth("tester@slovensko.digital")
    get user_google_oauth2_omniauth_callback_path

    assert_redirected_to new_oauth_consent_url
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:google_oauth2)
  end

  private

  def google_auth(email)
    OmniAuth::AuthHash.new(provider: "google_oauth2", uid: SecureRandom.hex(8), info: { email: email, name: "Tester" })
  end
end
