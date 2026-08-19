# == Schema Information
#
# Table name: api_keys
#
#  id         :bigint           not null, primary key
#  identifier :string           not null
#  name       :string           not null
#  public_key :text             not null
#  revoked_at :datetime
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  tenant_id  :bigint           not null
#  user_id    :bigint
#
# Indexes
#
#  index_api_keys_on_identifier  (identifier) UNIQUE
#  index_api_keys_on_tenant_id   (tenant_id)
#  index_api_keys_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class ApiKey < ApplicationRecord
  belongs_to :tenant
  belongs_to :user, optional: true

  scope :active, -> { where(revoked_at: nil) }

  before_validation :generate_identifier, on: :create

  validates :identifier, presence: true, uniqueness: true
  validates :name, :public_key, presence: true
  validate :user_belongs_to_tenant

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
  end

  def revoked?
    revoked_at.present?
  end

  private

  def generate_identifier
    self.identifier ||= SecureRandom.uuid
  end

  def user_belongs_to_tenant
    return if user.blank? || tenant.blank?
    return if tenant.tenant_users.where(user_id: user.id).exists?

    errors.add(:user, "must belong to the key tenant")
  end
end
