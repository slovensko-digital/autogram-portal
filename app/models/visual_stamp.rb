# == Schema Information
#
# Table name: visual_stamps
#
#  id                 :bigint           not null, primary key
#  height             :decimal(10, 2)   not null
#  page               :integer          default(1), not null
#  purpose            :string           not null
#  text               :text
#  width              :decimal(10, 2)   not null
#  x                  :decimal(10, 2)   not null
#  y                  :decimal(10, 2)   not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  document_id        :bigint           not null
#  signer_contract_id :bigint           not null
#
# Indexes
#
#  idx_on_signer_contract_id_document_id_purpose_d86ba1c031  (signer_contract_id,document_id,purpose)
#  index_visual_stamps_on_document_id                        (document_id)
#  index_visual_stamps_on_signer_contract_id                 (signer_contract_id)
#
# Foreign Keys
#
#  fk_rails_...  (document_id => documents.id)
#  fk_rails_...  (signer_contract_id => signer_contracts.id)
#
class VisualStamp < ApplicationRecord
  DEFAULT_TEXT = "This document is signed electronically. Validate signatures in a PDF viewer or trusted validator.".freeze

  belongs_to :signer_contract
  belongs_to :document
  has_one_attached :file

  enum :purpose, { visual_method: "visual_method", qes_preparation: "qes_preparation" }

  validates :page, numericality: { only_integer: true, greater_than: 0 }
  validates :x, :y, numericality: { greater_than_or_equal_to: 0 }
  validates :width, :height, numericality: { greater_than: 0 }
  validates :text, length: { maximum: 500 }, allow_blank: true

  before_validation :set_default_text

  def stamped_document
    return unless file.attached?

    Document.new(blob: file.blob)
  end

  private

  def set_default_text
    self.text = DEFAULT_TEXT if text.blank?
  end
end
