# == Schema Information
#
# Table name: sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  error_message      :text
#  options            :jsonb
#  signing_started_at :datetime
#  status             :integer          default("pending"), not null
#  type               :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  signer_contract_id :bigint           not null
#
# Indexes
#
#  index_sessions_on_signer_contract_id  (signer_contract_id)
#  index_sessions_on_type                (type)
#
# Foreign Keys
#
#  fk_rails_...  (signer_contract_id => signer_contracts.id)
#
class AdesEvidenceSession < Session
  store_accessor :options, :verification_channel

  has_one :signature_verification, foreign_key: :session_id, dependent: :destroy
  has_one :signature_evidence_record, foreign_key: :session_id, dependent: :destroy

  validates :verification_channel, inclusion: { in: %w[sms] }

  def self.model_name
    Session.model_name
  end

  def self.available?(contract, recipient: nil)
    contract.allowed_methods.include?("ades") && recipient&.mobile_phone?
  end

  def recipient_mobile_phone
    recipient&.mobile_phone
  end

  def recipient_masked_mobile_phone
    recipient&.masked_mobile_phone
  end

  def verification_requested?
    signature_verification&.sent?
  end

  def verification_verified?
    signature_verification&.verified?
  end

  def verification_failed?
    signature_verification&.failed?
  end

  def ready_for_server_signing?
    pending? && verification_verified?
  end

  def ensure_signature_evidence_record!
    signature_evidence_record || create_signature_evidence_record!(
      signer_contract: signer_contract,
      state: "pending",
      canonical_payload: {
        "contract_uuid" => contract.uuid,
        "bundle_uuid" => contract.bundle&.uuid,
        "recipient_uuid" => recipient&.uuid,
        "recipient_email" => recipient&.email,
        "recipient_mobile_phone" => recipient_masked_mobile_phone,
        "verification_channel" => verification_channel,
        "events" => []
      }
    )
  end
end
