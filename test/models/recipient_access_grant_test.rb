# == Schema Information
#
# Table name: recipient_access_grants
#
#  id                          :bigint           not null, primary key
#  claim_jti                   :string           not null
#  claimed_by_email            :string           not null
#  consumed_at                 :datetime
#  expires_at                  :datetime         not null
#  revoked_at                  :datetime
#  token_digest                :string           not null
#  uuid                        :uuid             not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  claimed_by_external_user_id :string
#  portal_instance_id          :bigint           not null
#  recipient_id                :bigint           not null
#
# Indexes
#
#  index_recipient_access_grants_on_claim_jti           (claim_jti)
#  index_recipient_access_grants_on_expires_at          (expires_at)
#  index_recipient_access_grants_on_portal_instance_id  (portal_instance_id)
#  index_recipient_access_grants_on_recipient_id        (recipient_id)
#  index_recipient_access_grants_on_token_digest        (token_digest) UNIQUE
#  index_recipient_access_grants_on_uuid                (uuid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (portal_instance_id => portal_instances.id)
#  fk_rails_...  (recipient_id => recipients.id)
#
require "test_helper"
require "openssl"

class RecipientAccessGrantTest < ActiveSupport::TestCase
  test "issue revokes prior active grants for the same portal and recipient" do
    recipient = create_recipient
    portal_instance = create_portal_instance
    first_grant = RecipientAccessGrant.issue!(
      recipient: recipient,
      portal_instance: portal_instance,
      claimed_by_email: recipient.email,
      claimed_by_external_user_id: "remote-1",
      claim_jti: SecureRandom.hex(16)
    )

    second_grant = RecipientAccessGrant.issue!(
      recipient: recipient,
      portal_instance: portal_instance,
      claimed_by_email: recipient.email,
      claimed_by_external_user_id: "remote-2",
      claim_jti: SecureRandom.hex(16)
    )

    assert_not first_grant.reload.active?
    assert second_grant.active?
    assert_not_nil second_grant.raw_token
  end

  private

  def create_recipient
    users(:one).update_column(:email, "owner@example.com")

    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 grant test"),
      filename: "grant-test.pdf",
      content_type: "application/pdf"
    )

    contract = Contract.create!(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )

    bundle = Bundle.create!(author: users(:one), contracts: [ contract ])
    bundle.recipients.create!(email: "recipient@example.com", locale: "en")
  end

  def create_portal_instance
    PortalInstance.create!(
      name: "Partner portal",
      base_url: "https://example.com",
      issuer: "https://issuer.example.com/#{SecureRandom.hex(4)}",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem,
      allowed_email_domains: [ "example.com" ]
    )
  end
end
