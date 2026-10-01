# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  completed_onboardings  :jsonb            not null
#  confirmation_sent_at   :datetime
#  confirmation_token     :string
#  confirmed_at           :datetime
#  current_sign_in_at     :datetime
#  current_sign_in_ip     :string
#  email                  :string
#  encrypted_password     :string           default(""), not null
#  failed_attempts        :integer          default(0), not null
#  features               :text             default([]), is an Array
#  last_sign_in_at        :datetime
#  last_sign_in_ip        :string
#  locale                 :string           default("sk")
#  locked_at              :datetime
#  name                   :string
#  qscd                   :integer
#  remember_created_at    :datetime
#  remember_token         :string
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  sign_in_count          :integer          default(0), not null
#  unconfirmed_email      :string
#  unlock_token           :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  last_tenant_id         :bigint
#
# Indexes
#
#  index_users_on_confirmation_token    (confirmation_token) UNIQUE
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_last_tenant_id        (last_tenant_id)
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#  index_users_on_unlock_token          (unlock_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (last_tenant_id => tenants.id) ON DELETE => nullify
#
class User < ApplicationRecord
  devise :magic_link_authenticatable, :omniauthable, :registerable, :confirmable, :rememberable, :validatable, :lockable

  attribute :features, :string, array: true, default: []
  AVAILABLE_FEATURES = %w[admin federation].freeze

  has_many :memberships, dependent: :destroy
  has_many :tenants, through: :memberships
  belongs_to :last_tenant, class_name: "Tenant", optional: true
  has_many :identities, dependent: :destroy
  has_many :signers, dependent: :destroy
  has_many :policy_consents, class_name: "UserPolicyConsent", dependent: :destroy

  enum :qscd, { none: 0, eid_2013: 1, eid_2021: 2, eid_2022: 3, eid_2024: 4, dpb_2014: 5, dpb_2020: 6, dpb_2023: 7 }, prefix: true
  MOBILE_QSCDS = [ "eid_2022", "eid_2024", "dpb_2023" ].freeze

  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_nil: true
  validates :agree_to_policies, acceptance: true, on: :create

  # Every user has a personal Basic tenant, including users invited to an organization.
  after_create :create_personal_tenant
  before_destroy :release_tenants, prepend: true

  # Returns the User record for the given OmniAuth payload, or nil for a brand-new
  # email address that still needs consent collection.
  #
  # Cases:
  #   1. Known identity          – returns the linked user immediately.
  #   2. Existing user by email  – links the new identity and returns the user.
  #   3. Brand-new email         – returns nil; caller should collect consent first.
  def self.find_or_link_from_provider_data(auth, locale: nil)
    identity = Identity.find_by(provider: auth.provider, uid: auth.uid)
    return identity.user if identity

    email = auth.info.email
    user = User.find_by(email: email)

    if user
      user.update!(name: auth.info.name) if user.name.blank?
      user.identities.create!(provider: auth.provider, uid: auth.uid)
      return user
    end

    nil
  end

  def accepted_current_policies?
    PolicyVersions.current.all? do |policy_type, version|
      policy_consents.for_policy(policy_type, version).exists?
    end
  end

  def display_name
    if name.present?
      "#{name} <#{email}>"
    else
      email
    end
  end

  # Finds the user for +email+ (normalized like Devise sign-in) or creates one for
  # a tenant invitation. The invitation email carries the confirmation link
  # instead of Devise's own.
  def self.find_or_invite!(email, locale: nil)
    find_for_authentication(email: email) || new(email: email, locale: locale.presence || I18n.default_locale.to_s).tap do |user|
      user.skip_confirmation_notification!
      user.save!
    end
  end

  def member_of?(tenant)
    tenant.present? && memberships.exists?(tenant: tenant)
  end

  # Tenants the user cannot leave behind: they are the last owner, but others remain.
  def tenants_blocking_deletion
    tenants.merge(Membership.owner).select do |tenant|
      tenant.memberships.owner.where.not(user_id: id).none? && tenant.memberships.where.not(user_id: id).exists?
    end
  end

  def feature_enabled?(feature)
    features.include? feature.to_s
  end

  scope :with_feature, ->(feature) { where("? = ANY(features)", feature.to_s) }

  def admin?
    feature_enabled?(:admin)
  end

  def federation_enabled?
    feature_enabled?(:federation)
  end

  def onboarding_completed?(method)
    completed_onboardings.include?(method.to_s) && !User.legacy_eid_card?(qscd)
  end

  def mark_onboarding_complete!(method)
    unless onboarding_completed?(method)
      update!(completed_onboardings: completed_onboardings + [ method.to_s ])
    end
  end

  def self.legacy_eid_card?(qscd)
    qscd.present? && qscd.in?(%w[eid_2013 dpb_2014])
  end

  def self.mobile_qscd?(qscd)
    qscd.present? && qscd.in?(MOBILE_QSCDS)
  end

  private

  def create_personal_tenant
    tenant = Tenant.create_personal_for!(self)
    update_column(:last_tenant_id, tenant.id)
  end

  # Tenants where the user is the only member go away with the user; from shared
  # tenants only the membership is removed.
  def release_tenants
    if tenants_blocking_deletion.any?
      errors.add(:base, :last_tenant_owner)
      throw :abort
    end

    update_column(:last_tenant_id, nil) if last_tenant_id
    tenants.each do |tenant|
      tenant.destroy! if tenant.memberships.where.not(user_id: id).none?
    end
  end
end
