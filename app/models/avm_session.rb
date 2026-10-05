# == Schema Information
#
# Table name: sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  error_message      :text
#  options            :jsonb
#  signing_started_at :datetime
#  status             :integer          default(0), not null
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
class AvmSession < Session
  store_accessor :options, :encryption_key, :document_identifier

  validates :document_identifier, :encryption_key, presence: true

  def self.model_name
    Session.model_name
  end

  def self.available?(qscd, contract)
    unavailability_reasons(qscd, contract).empty?
  end

  def self.unavailability_reasons(qscd, contract)
    reasons = []
    reasons << :multiple_files if contract.documents.count > 1
    reasons << :unsupported_qscd if qscd.present? && !User.mobile_qscd?(qscd)
    reasons << :timestamp_limit_reached if timestamped_level?(contract) && contract.tenant&.within_limit?(:timestamps) == false
    reasons
  end

  # AVM adds the timestamp of T and higher levels itself.
  def self.timestamped_level?(contract)
    contract.signature_parameters.present? && contract.signature_parameters.level != "BASELINE_B"
  end

  def adds_portal_timestamp?
    self.class.timestamped_level?(contract)
  end

  def avm_url
    "https://autogram.slovensko.digital/api/v1/qr-code?guid=#{document_identifier}&key=#{encryption_key}"
  end

  def avm_custom_url
    "avm://autogram.slovensko.digital/api/v1/qr-code?guid=#{document_identifier}&key=#{encryption_key}"
  end

  def expired?
    return false unless signing_started_at
    Time.current > signing_started_at + 10.minutes # 10 minute timeout
  end

  def mark_failed!(message = nil)
    super(message)
  end

  def process_webhook(_)
    Avm::DownloadSignedFileJob.perform_later(self)
  end
end
