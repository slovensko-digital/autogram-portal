# == Schema Information
#
# Table name: signature_evidence_records
#
#  id                          :bigint           not null, primary key
#  canonical_payload           :jsonb            not null
#  locked_at                   :datetime
#  manifest_sha256             :string
#  payload_sha256              :string
#  public_reference            :string           not null
#  signed_manifest             :text
#  state                       :string           default("pending"), not null
#  uuid                        :uuid             not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  contract_content_version_id :bigint
#  session_id                  :bigint           not null
#  signer_contract_id          :bigint           not null
#
# Indexes
#
#  idx_on_contract_content_version_id_e898efe78b           (contract_content_version_id)
#  index_signature_evidence_records_on_public_reference    (public_reference) UNIQUE
#  index_signature_evidence_records_on_session_id          (session_id)
#  index_signature_evidence_records_on_signer_contract_id  (signer_contract_id)
#  index_signature_evidence_records_on_state               (state)
#  index_signature_evidence_records_on_uuid                (uuid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (contract_content_version_id => contract_content_versions.id)
#  fk_rails_...  (session_id => sessions.id)
#  fk_rails_...  (signer_contract_id => signer_contracts.id)
#
class SignatureEvidenceRecord < ApplicationRecord
  belongs_to :session, class_name: "Session"
  belongs_to :signer_contract
  belongs_to :contract_content_version, optional: true
  has_one_attached :sealed_evidence
  has_one_attached :private_evidence_package

  enum :state, {
    pending: "pending",
    requested: "requested",
    verified: "verified",
    signed: "signed"
  }, scopes: false

  validates :uuid, :public_reference, presence: true, uniqueness: true

  before_validation :ensure_uuid
  before_validation :ensure_public_reference
  before_validation :refresh_payload_sha256

  def append_event!(type:, details: {}, occurred_at: Time.current)
    payload = (canonical_payload || {}).deep_dup
    events = Array(payload["events"])
    events << {
      "type" => type,
      "occurred_at" => occurred_at.iso8601,
      "details" => details.as_json
    }
    payload["events"] = events
    self.canonical_payload = payload
    save!
  end

  def signed_manifest_payload
    return {} if signed_manifest.blank?

    JSON.parse(signed_manifest)
  rescue JSON::ParserError
    {}
  end

  def signed_at
    value = signed_manifest_payload["signed_at"]
    value.present? ? Time.zone.parse(value) : nil
  rescue ArgumentError
    nil
  end

  def signed_by
    signed_manifest_payload["signed_by"].presence
  end

  def issued_by
    signed_manifest_payload["issued_by"].presence
  end

  def verification_channel_label
    signed_manifest_payload["verification_channel"].presence || canonical_payload["verification_channel"].presence
  end

  def public_event_time(type)
    event = Array(canonical_payload["events"]).find { |entry| entry["type"] == type }
    value = event&.dig("occurred_at")
    value.present? ? Time.zone.parse(value) : nil
  rescue ArgumentError
    nil
  end

  def validation_summary
    stored_record = contract_content_version&.contract_validation_record
    return stored_validation_summary(stored_record) if stored_record.present?

    live_validation_summary
  end

  def evidence_seal_summary
    manifest = signed_manifest_payload
    seal = manifest["seal"]
    return { status: :missing } if seal.blank?

    signature_base64 = seal["signature"].to_s
    certificate_pem = seal.dig("certificate", "pem").to_s
    signed_json_sha256 = seal["signed_json_sha256"].to_s
    return { status: :invalid, reason: :incomplete } if signature_base64.blank? || certificate_pem.blank? || signed_json_sha256.blank?

    unsigned_manifest = manifest.except("seal")
    canonical_unsigned_manifest = JSON.generate(deep_sort_value(unsigned_manifest))
    current_payload_sha256 = Digest::SHA256.hexdigest(canonical_payload_json)

    return { status: :invalid, reason: :signed_json_digest_mismatch } unless Digest::SHA256.hexdigest(canonical_unsigned_manifest) == signed_json_sha256
    return { status: :invalid, reason: :payload_digest_mismatch } unless manifest.dig("evidence", "payload_sha256") == current_payload_sha256
    return { status: :invalid, reason: :reference_mismatch } unless manifest["reference"] == public_reference

    certificate = OpenSSL::X509::Certificate.new(certificate_pem)
    signature = Base64.strict_decode64(signature_base64)
    valid = certificate.public_key.verify(OpenSSL::Digest::SHA256.new, signature, canonical_unsigned_manifest)

    {
      status: valid ? :valid : :invalid,
      reason: valid ? nil : :signature_mismatch,
      certificate_sha256: seal.dig("certificate", "sha256"),
      signed_json_sha256: signed_json_sha256,
      current_payload_sha256: current_payload_sha256
    }
  rescue OpenSSL::OpenSSLError, ArgumentError
    { status: :invalid, reason: :unreadable }
  end

  def attach_sealed_evidence!(payload)
    sealed_evidence.attach(
      io: StringIO.new(payload),
      filename: "signature-evidence-#{public_reference}.json",
      content_type: "application/json"
    )
  end

  def attach_private_evidence_package!(payload)
    private_evidence_package.attach(
      io: StringIO.new(payload),
      filename: "signature-evidence-#{public_reference}-private.asice",
      content_type: "application/vnd.etsi.asic-e+zip"
    )
  end

  def private_evidence_accessible_by?(user)
    return false unless user

    contract = session.contract
    return contract.bundle.author == user if contract.bundle.present?

    contract.user == user
  end

  def canonical_payload_for_sealing
    deep_sort_value(canonical_payload || {})
  end

  def canonical_payload_json
    JSON.generate(canonical_payload_for_sealing)
  end

  private

  def stored_validation_summary(stored_record)
    signatures = Array(stored_record.validation_details["signatures"])

    {
      source: :stored,
      signatures: signatures,
      all_signatures_valid: stored_record.all_signatures_valid?,
      all_signatures_total_passed: stored_record.all_signatures_total_passed?,
      expires_at: stored_record.expires_at,
      latest_archive_timestamp_expires_at: stored_record.latest_archive_timestamp_expires_at
    }
  end

  def live_validation_summary
    return { source: :missing, signatures: [] } if contract_content_version.blank?

    validation_result = contract_content_version.validation_result(skip_cache: true)
    {
      source: :live,
      signatures: Array(validation_result&.signatures).map do |signature|
        {
          "signer_name" => signature.signerName,
          "signing_time" => signature.signingTime&.iso8601,
          "signature_level" => signature.signatureLevel,
          "validation_result" => signature.validationResult,
          "valid" => signature.valid,
          "agp_reference" => signature.agpReference,
          "agp_instance" => signature.agpInstance,
          "certificate" => {
            "subject" => signature.certificateInfo[:subject],
            "issuer" => signature.certificateInfo[:issuer],
            "qualification" => signature.certificateInfo[:qualification],
            "not_after" => signature.certificateInfo[:notAfter]
          },
          "timestamps" => Array(signature.timestampInfo&.dig(:timestamps)).map do |timestamp|
            {
              "type" => timestamp.type,
              "time" => timestamp.time&.iso8601,
              "qualification" => timestamp.qualification,
              "subject" => timestamp.subject,
              "not_after" => timestamp.notAfter
            }
          end
        }
      end,
      all_signatures_valid: Array(validation_result&.signatures).all?(&:valid),
      all_signatures_total_passed: Array(validation_result&.signatures).all? { |signature| signature.validationResult == "TOTAL_PASSED" }
    }
  rescue StandardError => e
    {
      source: :error,
      signatures: [],
      error_message: e.message
    }
  end

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def ensure_public_reference
    self.public_reference ||= uuid.presence || SecureRandom.uuid
  end

  def refresh_payload_sha256
    self.payload_sha256 = Digest::SHA256.hexdigest(canonical_payload_json)
  end

  def deep_sort_value(value)
    case value
    when Hash
      value.keys.sort.each_with_object({}) do |key, sorted|
        sorted[key] = deep_sort_value(value[key])
      end
    when Array
      value.map { |item| deep_sort_value(item) }
    else
      value
    end
  end
end
