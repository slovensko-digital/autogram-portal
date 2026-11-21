require "test_helper"

class RecipientsHelperTest < ActionView::TestCase
  test "status badge shows the recipient's signing status" do
    bundle = bundles(:one)
    pending = bundle.recipients.create!(email: "pending@example.com")
    signed = bundle.recipients.create!(email: "signed@example.com")
    declined = bundle.recipients.create!(email: "declined@example.com")
    withdrawn = bundle.recipients.create!(email: "withdrawn@example.com")
    superseded = bundle.recipients.create!(email: "superseded@example.com")
    signed.signer_contracts.update_all(signed_at: Time.current)
    declined.signer_contracts.update_all(declined_at: Time.current)
    withdrawn.withdraw!
    superseded.signer_contracts.update_all(superseded_at: Time.current)

    expected = { pending => :pending, signed => :signed, declined => :declined, withdrawn.reload => :withdrawn, superseded => :superseded }
    I18n.with_locale(:en) do
      expected.each do |recipient, status|
        assert_equal status, recipient.signing_status, recipient.email
        assert_includes recipient_status_badge(recipient), t("helpers.recipients.status.#{status}"), recipient.email
      end
    end
  end
end
