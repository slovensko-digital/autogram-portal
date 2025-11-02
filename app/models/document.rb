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

  def validation_result(skip_cache: false)
    return get_new_validation_result if skip_cache

    cache_key = "document/#{id}/validation/#{updated_at.to_i}"
    @validation_result ||= Rails.cache.fetch(cache_key, expires_in: 5.minutes, race_condition_ttl: 10.seconds) do
      get_new_validation_result
    end
  end

  def extendable_signatures?
    return false unless has_signatures?
    validation_result.signatures.any? { |signature| signature[:timestamp_info].nil? }
  end

  def has_signatures?
    validation_result.has_signatures
  end

  def is_pdf?
    content_type&.include?("application/pdf")
  end

  def is_xml?
    content_type&.in?([ "application/xml", "text/xml" ])
  end

  def is_asice?
    content_type == "application/vnd.etsi.asic-e+zip"
  end

  def signature_options
    signature_form, container_type = validation_result.document_info[:signature_form], validation_result.document_info[:container_type]
    if has_signatures?
      case [ signature_form, container_type ]
      when [ "PAdES", nil ]
        return [ Ades::SignatureParameters::PADES ]
      when [ "XAdES", "ASiC_E" ]
        return [ Ades::SignatureParameters::XADES_ASICE ]
      when [ "CAdES", "ASiC_E" ]
        return [ Ades::SignatureParameters::CADES_ASICE ]
      else
        raise "Unknown signature form and container type combination: #{signature_form} + #{container_type}"
      end
    end

    [
      is_pdf? ? Ades::SignatureParameters::PADES : nil,
      Ades::SignatureParameters::XADES_ASICE,
      Ades::SignatureParameters::CADES_ASICE
    ].compact
  end

  def visualize(skip_cache: false)
    if blob.content_type.in?([ "text/plain", "image/png", "image/jpg", "image/jpeg" ])
      content_data = blob.download
      content_data = Base64.strict_encode64(content_data)
      return { mime_type: blob.content_type + ";base64", content: content_data }
    end

    return get_new_visualization_result if skip_cache

    cache_key = "document/#{id}/visualization/#{updated_at.to_i}"
    Rails.cache.fetch(cache_key, expires_in: 5.minutes, race_condition_ttl: 10.seconds) do
      get_new_visualization_result
    end
  end

  def short_uuid
    uuid.first(8)
  end

  def extend_signatures!
    extended_content = AutogramEnvironment.autogram_service.extend_signatures(self)

    raise "No extended content received from Autogram service" if extended_content.nil?

    blob.attach(
      io: StringIO.new(extended_content),
      filename: filename,
      content_type: content_type
    )
    save!
  end

  private

  def ensure_uuid
    self.uuid ||= SecureRandom.uuid
  end

  def acceptable_file_type
    return unless blob.attached?

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
      errors.add(:blob, "This file type is not supported. Supported types are: PDF, XML, XDCF, ASIC, TXT, PNG, JPG, JPEG.")
    end
  end

  def get_new_validation_result
    AutogramEnvironment.autogram_service.validate_signatures(self)
  end

  def get_new_visualization_result
    AutogramEnvironment.autogram_service.visualize_document(self)
  end
end
