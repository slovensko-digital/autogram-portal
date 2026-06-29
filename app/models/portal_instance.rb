# == Schema Information
#
# Table name: portal_instances
#
#  id                    :bigint           not null, primary key
#  allowed_email_domains :string           default([]), not null, is an Array
#  base_url              :string           not null
#  capabilities          :jsonb            not null
#  issuer                :string           not null
#  last_verified_at      :datetime
#  metadata              :jsonb            not null
#  name                  :string           not null
#  outbound_kid          :string
#  public_key_pem        :text             not null
#  status                :string           default("verified"), not null
#  uuid                  :uuid             not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
# Indexes
#
#  index_portal_instances_on_issuer  (issuer) UNIQUE
#  index_portal_instances_on_status  (status)
#  index_portal_instances_on_uuid    (uuid) UNIQUE
#
class PortalInstance < ApplicationRecord
  has_many :recipients, dependent: :restrict_with_exception

  enum :status, { pending: "pending", verified: "verified", revoked: "revoked" }, scopes: false

  before_validation :ensure_uuid, on: :create
  before_validation :normalize_fields

  validates :uuid, presence: true, uniqueness: true
  validates :uuid, format: { with: /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/, message: "must be a valid UUID" }
  validates :name, :base_url, :issuer, :public_key_pem, presence: true
  validates :issuer, uniqueness: true
  validates :base_url, portal_instance_url: true
  validate :base_url_must_not_include_path_or_query

  scope :trusted, -> { where(status: "verified") }

  def trusted?
    verified?
  end

  def matches_email_domain?(email)
    domain = email.to_s.split("@", 2).last.to_s.downcase
    domain.present? && allowed_email_domains.include?(domain)
  end

  def canonical_origin
    base_url
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def normalize_fields
    self.base_url = normalize_url(base_url)
    self.issuer = normalize_url(issuer)
    self.allowed_email_domains = Array(allowed_email_domains)
      .flat_map { |domain| domain.to_s.split(",") }
      .filter_map { |domain| domain.to_s.strip.downcase.presence }
      .uniq
  end

  def normalize_url(value)
    value.to_s.strip.sub(%r{/\z}, "").presence
  end

  def base_url_must_not_include_path_or_query
    return if base_url.blank?

    uri = URI.parse(base_url)
    path = uri.path.to_s

    if path.present? && path != "/"
      errors.add(:base_url, "must not include a path")
    end

    if uri.query.present? || uri.fragment.present?
      errors.add(:base_url, "must not include query or fragment")
    end
  rescue URI::InvalidURIError
    # Handled by the URL validator.
  end
end
