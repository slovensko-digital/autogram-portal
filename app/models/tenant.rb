# == Schema Information
#
# Table name: tenants
#
#  id                   :bigint           not null, primary key
#  api_token_public_key :string
#  features             :string           default([]), not null, is an Array
#  name                 :string           not null
#  personal             :boolean          default(FALSE), not null
#  plan                 :string           default("basic"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_tenants_on_plan  (plan)
#
class Tenant < ApplicationRecord
  AVAILABLE_FEATURES = %w[archivation api].freeze
  # nil means unlimited
  MAX_MEMBERS = { "basic" => 1, "pro" => nil }.freeze

  enum :plan, { basic: "basic", pro: "pro" }, validate: true

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :owner_memberships, -> { owner }, class_name: "Membership"
  has_many :owners, through: :owner_memberships, source: :user
  has_many :bundles, dependent: :destroy
  has_many :contracts, dependent: :destroy
  has_many :contract_validation_records, dependent: :destroy

  validates :name, presence: true
  validate :members_fit_plan, if: :plan_changed?
  validate :api_token_public_key_is_valid, if: -> { api_token_public_key.present? && api_token_public_key_changed? }

  before_validation :normalize_features

  scope :with_feature, ->(feature) { where("? = ANY(features)", feature.to_s) }

  def self.create_personal_for!(user)
    transaction do
      create!(name: user.name.presence || user.email, personal: true).tap do |tenant|
        tenant.memberships.create!(user: user, role: :owner)
      end
    end
  end

  def feature_enabled?(feature)
    features.include? feature.to_s
  end

  def archivation_enabled?
    feature_enabled?(:archivation)
  end

  def api_enabled?
    feature_enabled?(:api)
  end

  def signature_request_allowed?
    # TODO: verify tenant first before allowing them to send signature requests
    true
  end

  def signature_extension_allowed?
    true
  end

  def max_members
    MAX_MEMBERS.fetch(plan)
  end

  def can_add_member?
    max_members.nil? || memberships.count < max_members
  end

  def owner?(user)
    user.present? && memberships.owner.exists?(user: user)
  end

  # Owners get the author notifications of the tenant's bundles and contracts,
  # except for whoever caused them.
  def notification_recipients(except: nil)
    owners.where.not(id: except&.id).to_a
  end

  private

  def normalize_features
    self.features = Array(features).map(&:to_s).reject(&:blank?).uniq & AVAILABLE_FEATURES
  end

  def members_fit_plan
    return if max_members.nil?
    return unless persisted? && memberships.count > max_members

    errors.add(:plan, :too_many_members, count: max_members)
  end

  def api_token_public_key_is_valid
    OpenSSL::PKey.read(api_token_public_key)
  rescue OpenSSL::PKey::PKeyError, ArgumentError
    errors.add(:api_token_public_key, :invalid)
  end
end
