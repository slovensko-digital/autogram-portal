# == Schema Information
#
# Table name: signature_verifications
#
#  id                  :bigint           not null, primary key
#  attempts_count      :integer          default(0), not null
#  channel             :string           not null
#  code_digest         :string           not null
#  destination_digest  :string           not null
#  expires_at          :datetime
#  last_request_ip     :string
#  last_user_agent     :string
#  sent_at             :datetime
#  state               :string           default("pending"), not null
#  verified_at         :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  provider_request_id :string
#  session_id          :bigint           not null
#
# Indexes
#
#  index_signature_verifications_on_expires_at  (expires_at)
#  index_signature_verifications_on_session_id  (session_id)
#  index_signature_verifications_on_state       (state)
#
# Foreign Keys
#
#  fk_rails_...  (session_id => sessions.id)
#
class SignatureVerification < ApplicationRecord
  MAX_ATTEMPTS = 5

  belongs_to :session, class_name: "Session"

  encrypts :destination

  enum :channel, { sms: "sms", email: "email" }, scopes: false
  enum :state, {
    pending: "pending",
    sent: "sent",
    verified: "verified",
    expired: "expired",
    failed: "failed"
  }, scopes: false

  validates :code_digest, :destination_digest, presence: true
  validates :attempts_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  attribute :destination, :string

  def expired_now?(reference_time = Time.current)
    expires_at.present? && expires_at <= reference_time
  end

  def attempts_remaining
    MAX_ATTEMPTS - attempts_count.to_i
  end
end
