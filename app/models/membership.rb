# == Schema Information
#
# Table name: memberships
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
#  index_memberships_on_tenant_id              (tenant_id)
#  index_memberships_on_tenant_id_and_user_id  (tenant_id,user_id) UNIQUE
#  index_memberships_on_user_id                (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (tenant_id => tenants.id)
#  fk_rails_...  (user_id => users.id)
#
class Membership < ApplicationRecord
  belongs_to :tenant
  belongs_to :user

  enum :role, { owner: "owner", member: "member" }, validate: true

  validates :user_id, uniqueness: { scope: :tenant_id }
  validate :tenant_has_free_seat, on: :create
  validate :keeps_an_owner, on: :update, if: -> { role_changed?(from: "owner") }

  before_destroy :ensure_not_last_owner, unless: -> { destroyed_by_association }

  def last_owner?
    owner? && tenant.memberships.owner.where.not(id: id).none?
  end

  private

  def tenant_has_free_seat
    return if tenant.nil? || tenant.can_add_member?

    errors.add(:base, :plan_member_limit, count: tenant.max_members)
  end

  def keeps_an_owner
    return unless tenant.memberships.owner.where.not(id: id).none?

    errors.add(:role, :last_owner)
  end

  def ensure_not_last_owner
    return unless last_owner?

    errors.add(:base, :last_owner)
    throw :abort
  end
end
