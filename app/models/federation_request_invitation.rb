# == Schema Information
#
# Table name: federation_request_invitations
#
#  id                    :bigint           not null, primary key
#  origin_bundle_uuid    :uuid             not null
#  origin_recipient_uuid :uuid             not null
#  payload               :jsonb            not null
#  recipient_email       :string           not null
#  status                :string           default("pending"), not null
#  uuid                  :uuid             not null
#  withdrawn_at          :datetime
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  portal_instance_id    :bigint           not null
#  recipient_user_id     :bigint
#
# Indexes
#
#  index_federation_request_invitations_on_portal_and_recipient  (portal_instance_id,origin_recipient_uuid) UNIQUE
#  index_federation_request_invitations_on_recipient_email       (recipient_email)
#  index_federation_request_invitations_on_recipient_user_id     (recipient_user_id)
#  index_federation_request_invitations_on_status                (status)
#  index_federation_request_invitations_on_uuid                  (uuid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (portal_instance_id => portal_instances.id)
#  fk_rails_...  (recipient_user_id => users.id)
#
class FederationRequestInvitation < ApplicationRecord
  RESOLVED_STATUSES = %w[signed superseded withdrawn].freeze

  belongs_to :portal_instance
  belongs_to :recipient_user, class_name: "User", optional: true

  enum :status, { pending: "pending", signed: "signed", superseded: "superseded", withdrawn: "withdrawn" }, scopes: false

  scope :pending, -> { where(status: "pending") }
  scope :visible_in_received, -> { where.not(status: "withdrawn") }
  scope :for_user, ->(user) {
    where(recipient_email: user.email)
      .or(where(recipient_user: user))
      .distinct
  }

  before_validation :ensure_uuid, on: :create
  before_validation :match_recipient_user

  validates :uuid, presence: true, uniqueness: true
  validates :uuid,
    format: { with: /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/, message: "must be a valid UUID" }
  validates :origin_recipient_uuid, :origin_bundle_uuid, :recipient_email, presence: true
  validates :origin_recipient_uuid, uniqueness: { scope: :portal_instance_id }
  validates :recipient_email, format: { with: URI::MailTo::EMAIL_REGEXP }

  def to_param
    uuid
  end

  def resolve!(status:)
    normalized_status = status.to_s
    raise ArgumentError, "Unsupported invitation status" unless RESOLVED_STATUSES.include?(normalized_status)
    return if self.status == normalized_status

    update!(status: normalized_status, withdrawn_at: Time.current)
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def match_recipient_user
    return if recipient_email.blank?

    self.recipient_user = User.find_by(email: recipient_email)
  end
end
