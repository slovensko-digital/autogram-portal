# == Schema Information
#
# Table name: documents
#
#  id          :bigint           not null, primary key
#  remote_hash :string
#  url         :string
#  uuid        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  contract_id :bigint
#  user_id     :bigint
#
# Indexes
#
#  index_documents_on_contract_id  (contract_id)
#  index_documents_on_user_id      (user_id)
#  index_documents_on_uuid         (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (user_id => users.id)
#
class Document < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :contract, optional: true

  has_one :xdc_parameters, class_name: "XdcParameters", dependent: :destroy
  has_one_attached :blob

  accepts_nested_attributes_for :xdc_parameters

  validates :blob, presence: { message: "A file needs to be attached" }
  validate :acceptable_file_type
  validates :xdc_parameters, presence: true, if: -> { blob.attached? && blob.content_type == "application/vnd.gov.sk.xmldatacontainer+xml" }
  validates :uuid, presence: true, uniqueness: true

  before_validation :ensure_uuid, on: :create

  # Use UUID in URLs instead of ID for security
  def to_param
    uuid
  end

  def filename
    blob.attached? ? blob.filename.to_s : nil
  end

  def content
    blob.attached? ? blob.download : nil
  end

  def content_type
    blob.attached? ? blob.content_type : nil
  end

  def signature_parameters
    return contract&.signature_parameters if contract

    AutogramEnvironment.autogram_service.default_signature_parameters(content_type)
  end

  def validate_signatures
    AutogramEnvironment.autogram_service.validate_signatures(self)
  end

  def has_signatures?
    validate_signatures.has_signatures
  end

  def visualize
    if blob.content_type.in?(["text/plain", "image/png", "image/jpg", "image/jpeg"])
      content_data = blob.download
      content_data = Base64.strict_encode64(content_data)
      return { mime_type: blob.content_type + ";base64", content: content_data }
    end

    AutogramEnvironment.autogram_service.visualize_document(self)
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def acceptable_file_type
    return unless blob.attached?

    # .pdf,.xml,.xdcf,.txt,.png,.jpg,.jpeg,application/pdf,application/xml,text/xml,application/vnd.gov.sk.xmldatacontainer+xml,application/vnd.etsi.asic-e+zip
    acceptable_types = [
      "application/pdf",
      "application/xml",
      "text/xml",
      "application/vnd.gov.sk.xmldatacontainer+xml",
      "application/vnd.etsi.asic-e+zip",
      "text/plain",
      "image/png",
      "image/jpg",
      "image/jpeg"
    ]

    unless acceptable_types.include?(blob.content_type)
      errors.add(:blob, "Tento typ súboru nie je podporovaný. Podporované sú: PDF, XML, XDCF, TXT, PNG, JPG, JPEG súbory.")
    end
  end
end
