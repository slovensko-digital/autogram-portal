# == Schema Information
#
# Table name: signature_field_preparations
#
#  id               :bigint           not null, primary key
#  field_identifier :string           not null
#  height           :decimal(10, 2)   not null
#  page             :integer          default(1), not null
#  width            :decimal(10, 2)   not null
#  x                :decimal(10, 2)   not null
#  y                :decimal(10, 2)   not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  contract_id      :bigint           not null
#  document_id      :bigint           not null
#  recipient_id     :bigint           not null
#
# Indexes
#
#  idx_signature_fields_on_recipient_contract_document     (recipient_id,contract_id,document_id) UNIQUE
#  index_signature_field_preparations_on_contract_id       (contract_id)
#  index_signature_field_preparations_on_document_id       (document_id)
#  index_signature_field_preparations_on_field_identifier  (field_identifier) UNIQUE
#  index_signature_field_preparations_on_recipient_id      (recipient_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#  fk_rails_...  (document_id => documents.id)
#  fk_rails_...  (recipient_id => recipients.id)
#
class SignatureFieldPreparation < ApplicationRecord
  belongs_to :contract
  belongs_to :document
  belongs_to :recipient

  validates :field_identifier, presence: true, uniqueness: true
  validates :recipient_id, uniqueness: { scope: [ :contract_id, :document_id ] }
  validates :page, numericality: { only_integer: true, greater_than: 0 }
  validates :x, :y, numericality: { greater_than_or_equal_to: 0 }
  validates :width, :height, numericality: { greater_than: 0 }

  validate :contract_must_allow_field_preparation
  validate :document_must_belong_to_contract
  validate :document_must_be_pdf
  validate :recipient_must_belong_to_contract_bundle

  before_validation :assign_field_identifier, on: :create

  def bundle
    contract&.bundle
  end

  private

  def assign_field_identifier
    self.field_identifier ||= "signature-field-#{SecureRandom.uuid}"
  end

  def contract_must_allow_field_preparation
    return if contract.blank?
    return if contract.pades_field_preparation_allowed?

    errors.add(:contract, "does not allow PAdES signature field preparation")
  end

  def document_must_belong_to_contract
    return if contract.blank? || document.blank?
    return if document.contract_id == contract_id

    errors.add(:document, "must belong to the contract")
  end

  def document_must_be_pdf
    return if document.blank?
    return if document.is_pdf?

    errors.add(:document, "must be a PDF")
  end

  def recipient_must_belong_to_contract_bundle
    return if recipient.blank? || contract.blank? || contract.bundle.blank?
    return if recipient.bundle_id == contract.bundle_id

    errors.add(:recipient, "must belong to the contract bundle")
  end
end
