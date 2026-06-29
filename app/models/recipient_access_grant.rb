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
class RecipientAccessGrant < ApplicationRecord
  TOKEN_BYTES = 32
  DEFAULT_TTL = 15.minutes

  attr_reader :raw_token

  belongs_to :recipient
  belongs_to :portal_instance

  before_validation :ensure_uuid, on: :create

  validates :uuid, presence: true, uniqueness: true
  validates :token_digest, :expires_at, :claimed_by_email, :claim_jti, presence: true

  scope :active, -> {
    where(consumed_at: nil, revoked_at: nil)
      .where("expires_at > ?", Time.current)
  }

  class << self
    def issue!(recipient:, portal_instance:, claimed_by_email:, claimed_by_external_user_id:, claim_jti:, expires_at: DEFAULT_TTL.from_now)
      token = SecureRandom.urlsafe_base64(TOKEN_BYTES)

      transaction do
        revoke_active_for!(recipient: recipient, portal_instance: portal_instance)

        grant = create!(
          recipient: recipient,
          portal_instance: portal_instance,
          token_digest: digest(token),
          expires_at: expires_at,
          claimed_by_email: claimed_by_email,
          claimed_by_external_user_id: claimed_by_external_user_id,
          claim_jti: claim_jti
        )

        grant.instance_variable_set(:@raw_token, token)
        grant
      end
    end

    def find_active_by_token(token)
      active.find_by(token_digest: digest(token))
    end

    def revoke_active_for!(recipient:, portal_instance: nil)
      scope = active.where(recipient: recipient)
      scope = scope.where(portal_instance: portal_instance) if portal_instance

      now = Time.current
      scope.update_all(revoked_at: now, updated_at: now)
    end

    private

    def digest(token)
      Digest::SHA256.hexdigest(token.to_s)
    end
  end

  def active?
    consumed_at.nil? && revoked_at.nil? && expires_at.future?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
