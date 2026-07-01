# == Schema Information
#
# Table name: contract_validation_records
#
#  id                                  :bigint           not null, primary key
#  document_hash                       :string           not null
#  expires_at                          :datetime
#  filename                            :string           not null
#  latest_archive_timestamp_expires_at :datetime
#  signature_levels                    :string           default([]), not null, is an Array
#  signatures_count                    :integer          default(0), not null
#  source_bundle_uuid                  :string
#  source_contract_uuid                :string           not null
#  source_version_number               :integer          not null
#  validation_details                  :jsonb            not null
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  contract_content_version_id         :bigint
#  contract_id                         :bigint
#  user_id                             :bigint           not null
#
# Indexes
#
#  idx_on_contract_content_version_id_7e3d0b9366                   (contract_content_version_id)
#  index_contract_validation_records_on_contract_id                (contract_id)
#  index_contract_validation_records_on_document_hash              (document_hash)
#  index_contract_validation_records_on_user_contract_and_version  (user_id,source_contract_uuid,source_version_number) UNIQUE
#  index_contract_validation_records_on_user_id                    (user_id)
#  index_contract_validation_records_on_user_id_and_expires_at     (user_id,expires_at)
#
# Foreign Keys
#
#  fk_rails_...  (contract_content_version_id => contract_content_versions.id) ON DELETE => nullify
#  fk_rails_...  (contract_id => contracts.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id)
#
class ContractValidationRecord < ApplicationRecord
  WARNING_WINDOW = 2.months

  belongs_to :user
  belongs_to :contract, optional: true
  belongs_to :contract_content_version, optional: true

  validates :source_contract_uuid, :source_version_number, :filename, :document_hash, presence: true
  validates :source_contract_uuid, uniqueness: { scope: [ :user_id, :source_version_number ] }
  validates :document_hash, format: { with: /\A\h{64}\z/ }

  scope :recent, -> { order(updated_at: :desc) }
  scope :expiring_before, ->(time) { where.not(expires_at: nil).where(expires_at: Time.current..time) }
  scope :expiring_within, ->(time = WARNING_WINDOW.from_now) { where.not(expires_at: nil).where(expires_at: Time.current..time) }
  scope :expired, -> { where.not(expires_at: nil).where("expires_at < ?", Time.current) }
  scope :latest_per_contract, -> {
    latest_records = except(:select, :order)
      .select("DISTINCT ON (#{table_name}.user_id, #{table_name}.source_contract_uuid) #{table_name}.*")
      .order(Arel.sql("#{table_name}.user_id, #{table_name}.source_contract_uuid, #{table_name}.source_version_number DESC, #{table_name}.updated_at DESC"))

    from("(#{latest_records.to_sql}) #{table_name}")
  }
  scope :expiring, -> { expiring_before(WARNING_WINDOW.from_now) }
  scope :healthy, -> { where.not(expires_at: nil).where("expires_at > ?", WARNING_WINDOW.from_now) }
  scope :notexpired, -> { where.not(expires_at: nil).where("expires_at > ?", Time.current) }
  scope :unknown, -> { where(expires_at: nil) }

  def self.capture!(contract:, contract_content_version:, validation_result:, signed_content:, filename:, session: nil)
    owner = contract.user || contract.bundle&.author
    return if owner.blank? || !owner.archivation_enabled?

    signature_snapshots = build_signature_snapshots(validation_result)
    record = find_or_initialize_by(
      user: owner,
      source_contract_uuid: contract.uuid,
      source_version_number: contract_content_version.version_number
    )

    record.assign_attributes(
      contract: contract,
      contract_content_version: contract_content_version,
      source_bundle_uuid: contract.bundle&.uuid,
      filename: filename,
      document_hash: Digest::SHA256.hexdigest(signed_content),
      signature_levels: validation_result.signatures.map(&:signatureLevel).compact.uniq,
      signatures_count: validation_result.signature_count,
      expires_at: signature_snapshots.filter_map { |snapshot| parse_time(snapshot["expires_at"]) }.min,
      latest_archive_timestamp_expires_at: signature_snapshots.filter_map { |snapshot| parse_time(snapshot["latest_archive_timestamp_expires_at"]) }.max,
      validation_details: {
        "captured_via" => session&.type,
        "content_origin" => contract_content_version.origin,
        "version_number" => contract_content_version.version_number,
        "document_info" => validation_result.documentInfo.as_json,
        "signatures" => signature_snapshots
      }
    )

    record.save!
    record
  end

  def expiring_soon?(reference_time = Time.current)
    expires_at.present? && expires_at >= reference_time && expires_at <= reference_time + WARNING_WINDOW
  end

  def expired?(reference_time = Time.current)
    expires_at.present? && expires_at < reference_time
  end

  def status(reference_time = Time.current)
    return :unknown if expires_at.blank?
    return :expired if expired?(reference_time)
    return :expiring if expiring_soon?(reference_time)

    :healthy
  end

  def source_contract_available?
    contract.present?
  end

  def source_content_available?
    contract_content_version.present?
  end

  def latest_for_contract?
    source_contract_available? && contract.latest_content_version == contract_content_version
  end

  def refreshable?(target_level: "LTA")
    return false unless user&.archivation_enabled?

    source_contract_available? &&
      source_content_available? &&
      latest_for_contract? &&
      contract_content_version.extendable_signatures?(target_level: target_level)
  rescue StandardError
    false
  end

  def refresh_action_available?(reference_time = Time.current)
    return false unless user&.archivation_enabled?

    source_contract_available? &&
      source_content_available? &&
      latest_for_contract? &&
      expires_at.present? &&
      all_signatures_valid? &&
      all_signatures_total_passed? &&
      (expires_at <= reference_time + WARNING_WINDOW || b_level_signature_present?)
  end

  def all_signatures_valid?
    Array(validation_details["signatures"]).all? { |signature| signature["valid"] }
  end

  def all_signatures_total_passed?
    Array(validation_details["signatures"]).all? { |signature| signature["validation_result"] == "TOTAL_PASSED" }
  end

  def b_level_signature_present?
    Array(validation_details["signatures"]).any? { |signature| signature["signature_level"] == "BASELINE_B" }
  end

  def signer_names
    Array(validation_details["signatures"]).filter_map { |signature| signature["signer_name"].presence }.uniq
  end

  def agp_reference
    Array(validation_details["signatures"]).filter_map { |signature| signature["agp_reference"].presence }.first
  end

  def agp_instance
    Array(validation_details["signatures"]).filter_map { |signature| signature["agp_instance"].presence }.first
  end

  class << self
    private

    def build_signature_snapshots(validation_result)
      validation_result.signatures.map do |signature|
        timestamps = Array(signature.timestampInfo&.dig(:timestamps))
        archive_expiry = latest_archive_timestamp_expiry(timestamps)
        signature_expiry = signature_expiry_at(signature, timestamps, archive_expiry)

        {
          "signer_name" => signature.signerName,
          "signing_time" => format_time(signature.signingTime),
          "signature_level" => signature.signatureLevel,
          "validation_result" => signature.validationResult,
          "valid" => signature.valid,
          "agp_reference" => signature.agpReference,
          "agp_instance" => signature.agpInstance,
          "certificate" => {
            "subject" => signature.certificateInfo[:subject],
            "issuer" => signature.certificateInfo[:issuer],
            "qualification" => signature.certificateInfo[:qualification],
            "not_after" => format_time(parse_time(signature.certificateInfo[:notAfter]))
          },
          "timestamps" => timestamps.map do |timestamp|
            {
              "type" => timestamp.type,
              "time" => format_time(timestamp.time),
              "qualification" => timestamp.qualification,
              "subject" => timestamp.subject,
              "not_after" => format_time(parse_time(timestamp.notAfter))
            }
          end,
          "signed_objects" => Array(signature.signedObjects).as_json,
          "unsigned_objects" => Array(signature.unsignedObjects).as_json,
          "latest_archive_timestamp_expires_at" => format_time(archive_expiry),
          "expires_at" => format_time(signature_expiry)
        }
      end
    end

    def latest_archive_timestamp_expiry(timestamps)
      timestamps
        .select { |timestamp| timestamp.type == "ARCHIVE_TIMESTAMP" }
        .filter_map { |timestamp| parse_time(timestamp.notAfter) }
        .max
    end

    def signature_expiry_at(signature, timestamps, archive_expiry)
      return archive_expiry if archive_expiry.present?

      [ parse_time(signature.certificateInfo[:notAfter]), *timestamps.filter_map { |timestamp| parse_time(timestamp.notAfter) } ].compact.min
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def format_time(value)
      parse_time(value)&.iso8601
    end
  end
end
