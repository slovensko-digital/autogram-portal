# == Schema Information
#
# Table name: api_token_uses
#
#  id         :bigint           not null, primary key
#  expires_at :datetime         not null
#  jti        :string           not null
#  created_at :datetime         not null
#  tenant_id  :bigint           not null
#
# Indexes
#
#  index_api_token_uses_on_expires_at         (expires_at)
#  index_api_token_uses_on_tenant_id_and_jti  (tenant_id,jti) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id) ON DELETE => cascade
#

# A token accepted by the tenant API (ApiTokenAuthenticator). Each jti is accepted only once per tenant,
# so a leaked token cannot be replayed; ApiTokenUsesCleanupJob deletes the rows of expired tokens.
class ApiTokenUse < ApplicationRecord
  belongs_to :tenant

  scope :expired, -> { where(expires_at: ...Time.current) }

  # Records the use of a token and tells whether it is its first use. The unique index decides
  # between concurrent requests with the same token.
  def self.record_first_use(tenant:, jti:, expires_at:)
    insert({ tenant_id: tenant.id, jti: jti, expires_at: expires_at }, unique_by: [ :tenant_id, :jti ], returning: :id).any?
  end
end
