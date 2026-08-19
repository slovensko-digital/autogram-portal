# == Schema Information
#
# Table name: tenant_users
#
#  id         :bigint           not null, primary key
#  role       :string           default("member"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  tenant_id  :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_tenant_users_on_tenant_id              (tenant_id)
#  index_tenant_users_on_tenant_id_and_user_id  (tenant_id,user_id) UNIQUE
#  index_tenant_users_on_user_id                (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class TenantUser < ApplicationRecord
  belongs_to :tenant
  belongs_to :user

  enum :role, { admin: "admin", member: "member" }, validate: true

  validates :user_id, uniqueness: { scope: :tenant_id }
  validate :freemium_tenant_has_one_member

  private

  def freemium_tenant_has_one_member
    return unless tenant&.freemium?

    Tenant.where(id: tenant.id).lock.pick(:id) if tenant.persisted?
    return unless tenant.tenant_users.where.not(id: id).exists?

    errors.add(:tenant, "freemium tenants can only have one member")
  end
end
