require "test_helper"

class TenantMailerTest < ActionMailer::TestCase
  setup do
    @tenant = tenants(:one)
    @tenant.update!(plan: :pro)
  end

  test "invitation of a new user is in their locale and carries the confirmation link" do
    user = User.find_or_invite!("invited-#{SecureRandom.hex(4)}@example.com", locale: "en")
    membership = @tenant.memberships.create!(user: user)

    mail = TenantMailer.with(membership: membership).invitation

    assert_equal [ user.email ], mail.to
    assert_equal I18n.t("tenant_mailer.invitation.subject", tenant: @tenant.name, locale: :en), mail.subject
    assert_includes mail.text_part.body.decoded, user.confirmation_token
  end

  test "invitation of a confirmed user links to the dashboard" do
    user = users(:two)
    user.update_columns(confirmed_at: Time.current, locale: "sk")
    membership = @tenant.memberships.create!(user: user)

    mail = TenantMailer.with(membership: membership).invitation

    assert_equal I18n.t("tenant_mailer.invitation.subject", tenant: @tenant.name, locale: :sk), mail.subject
    assert_includes mail.text_part.body.decoded, "/dashboard"
  end
end
