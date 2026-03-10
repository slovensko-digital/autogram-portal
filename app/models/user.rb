# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  api_token_public_key   :string
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
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  sign_in_count          :integer          default(0), not null
#  unconfirmed_email      :string
#  unlock_token           :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_users_on_confirmation_token    (confirmation_token) UNIQUE
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#  index_users_on_unlock_token          (unlock_token) UNIQUE
#
class User < ApplicationRecord
  devise :magic_link_authenticatable, :omniauthable, :registerable, :confirmable, :rememberable, :validatable, :lockable

  attribute :features, :string, array: true, default: []

  has_many :bundles, foreign_key: "user_id", dependent: :destroy
  has_many :identities, dependent: :destroy
  has_many :contracts, dependent: :destroy

  enum :qscd, { none: 0, eid_2013: 1, eid_2021: 2, eid_2022: 3, eid_2024: 4, dpb_2014: 5, dpb_2020: 6, dpb_2023: 7 }, prefix: true
  MOBILE_QSCDS = [ "eid_2022", "eid_2024", "dpb_2023" ].freeze

  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_nil: true

  def self.create_from_provider_data(auth, locale: nil)
    # Check if identity already exists
    identity = Identity.find_by(provider: auth.provider, uid: auth.uid)
    return identity.user if identity

    # Check if user exists with this email
    email = auth.info.email
    user = User.find_by(email: email)

    if user
      # Link identity to existing user and update name if blank
      user.update!(name: auth.info.name) if user.name.blank?
      user.identities.create!(provider: auth.provider, uid: auth.uid)
      return user
    end

    # Create new user with identity
    user = User.create!(
      email: email,
      name: auth.info.name,
      confirmed_at: Time.current,
      locale: locale || I18n.default_locale.to_s
    )
    user.identities.create!(provider: auth.provider, uid: auth.uid)
    user
  end

  def display_name
    name.presence || email
  end

  def feature_enabled?(feature)
    features.include? feature.to_s
  end

  def signature_request_allowed?
    # TODO: verify user first before allowing them to send signature requests
    true
  end

  def signature_extension_allowed?
    true
  end

  # Onboarding helper methods
  def onboarding_completed?(method)
    completed_onboardings.include?(method.to_s) && !User.legacy_eid_card?(qscd)
  end

  def mark_onboarding_complete!(method)
    unless onboarding_completed?(method)
      update!(completed_onboardings: completed_onboardings + [ method.to_s ])
    end
  end

  def self.supports_mobile_signing?(qscd)
    MOBILE_QSCDS.include?(qscd)
  end

  def self.legacy_eid_card?(qscd)
    qscd.present? && qscd.in?(%w[eid_2013 dpb_2014])
  end
end
