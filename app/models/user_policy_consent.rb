# == Schema Information
#
# Table name: user_policy_consents
#
#  id             :bigint           not null, primary key
#  accepted_at    :datetime         not null
#  ip_address     :string
#  policy_type    :string           not null
#  policy_version :string           not null
#  source         :string           not null
#  user_agent     :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_user_policy_consents_on_user_id                  (user_id)
#  index_user_policy_consents_on_user_id_and_accepted_at  (user_id,accepted_at)
#  index_user_policy_consents_on_user_policy_version      (user_id,policy_type,policy_version)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class UserPolicyConsent < ApplicationRecord
  POLICY_TYPES = %w[terms privacy].freeze
  SOURCES      = %w[email_signup google_oauth2 oauth_signup re_consent].freeze

  belongs_to :user

  validates :policy_type,    presence: true, inclusion: { in: POLICY_TYPES }
  validates :policy_version, presence: true
  validates :source,         presence: true, inclusion: { in: SOURCES }
  validates :accepted_at,    presence: true

  scope :for_policy, ->(type, version) { where(policy_type: type, policy_version: version) }

  # Records consent for every policy type whose current version has not yet been
  # accepted by +user+. Safe to call multiple times – skips already-recorded versions.
  def self.record_current_for(user:, source:, request:)
    PolicyVersions.current.each do |policy_type, version|
      next if user.policy_consents.for_policy(policy_type, version).exists?

      user.policy_consents.create!(
        policy_type:    policy_type,
        policy_version: version,
        source:         source,
        accepted_at:    Time.current,
        ip_address:     request.remote_ip,
        user_agent:     request.user_agent.to_s.truncate(512)
      )
    end
  end
end
