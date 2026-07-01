# == Schema Information
#
# Table name: contract_content_versions
#
#  id             :bigint           not null, primary key
#  origin         :string           default("signed"), not null
#  version_number :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  contract_id    :bigint           not null
#
# Indexes
#
#  idx_on_contract_id_version_number_0129589952    (contract_id,version_number) UNIQUE
#  index_contract_content_versions_on_contract_id  (contract_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#
class ContractContentVersion < ApplicationRecord
  READ_RETRIES = 3
  READ_RETRY_DELAY = 0.05

  belongs_to :contract
  has_one :contract_validation_record, dependent: :nullify
  has_one_attached :file

  validates :version_number, presence: true, uniqueness: { scope: :contract_id }
  validates :origin, presence: true

  def filename
    file.attached? ? file.filename.to_s : nil
  end

  def content
    return unless file.attached?

    attempts = 0

    begin
      attempts += 1
      file.download
    rescue ActiveStorage::FileNotFoundError, Errno::ENOENT
      raise if attempts >= READ_RETRIES

      sleep(READ_RETRY_DELAY * attempts)
      retry
    end
  end

  def content_type
    file.attached? ? file.content_type : nil
  end

  def document
    return unless file.attached?

    Document.new(blob: file.blob)
  end

  def validation_result(skip_cache: false)
    document&.validation_result(skip_cache: skip_cache)
  end

  def extendable_signatures?(target_level: "T")
    document&.extendable_signatures?(target_level: target_level) || false
  end

  def available_extension_target_levels
    document&.available_extension_target_levels || []
  end

  def extended_content(target_level: "T")
    raise ArgumentError, "Signed content is not attached" unless file.attached?

    AutogramEnvironment.autogram_service.extend_signatures(document, target_level: target_level)
  end
end
