# == Schema Information
#
# Table name: tenants
#
#  id                   :bigint           not null, primary key
#  api_token_identifier :string           not null
#  api_token_public_key :text
#  features             :text             default([]), not null, is an Array
#  kind                 :string           default("freemium"), not null
#  name                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_tenants_on_api_token_identifier  (api_token_identifier) UNIQUE
#
class Tenant < ApplicationRecord
  AVAILABLE_FEATURES = %w[archivation api federation].freeze

  enum :kind, { freemium: "freemium", organization: "organization" }, validate: true

  has_many :tenant_users, dependent: :destroy
  has_many :users, through: :tenant_users
  has_many :bundles, dependent: :destroy
  has_many :contracts, dependent: :destroy
  has_many :contract_validation_records, dependent: :destroy

  validates :name, presence: true
  validates :api_token_identifier, presence: true, uniqueness: true
  validate :features_are_available
  validate :freemium_has_at_most_one_member

  before_validation :generate_api_token_identifier, on: :create

  scope :with_feature, ->(feature) { where("? = ANY(features)", feature.to_s) }

  def feature_enabled?(feature)
    Array(features).include?(feature.to_s)
  end

  def archivation_enabled?
    feature_enabled?(:archivation)
  end

  def api_enabled?
    feature_enabled?(:api)
  end

  def federation_enabled?
    feature_enabled?(:federation)
  end

  private

  def features_are_available
    return errors.add(:features, "can't be nil") if features.nil?

    invalid_features = Array(features) - AVAILABLE_FEATURES
    errors.add(:features, "contains unsupported features: #{invalid_features.join(', ')}") if invalid_features.any?
  end

  def freemium_has_at_most_one_member
    return unless freemium?
    return unless tenant_users.reject(&:marked_for_destruction?).many?

    errors.add(:tenant_users, "freemium tenants can only have one member")
  end

  def generate_api_token_identifier
    self.api_token_identifier ||= SecureRandom.uuid
  end
end
