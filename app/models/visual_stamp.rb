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
  QES_MANDATORY_TEXT = "This document is signed electronically. Validate signatures in a PDF viewer or trusted validator.".freeze
  PADES_VISUAL_SIGNATURE_TEXT = "Electronically signed".freeze
  PADES_VISUAL_SIGNATURE_BY_PREFIX = "Electronically signed by".freeze
  DEFAULT_TEXT = QES_MANDATORY_TEXT
  MAX_WIDTH = 256
  MAX_HEIGHT = 200

  belongs_to :signer_contract
  belongs_to :document
  has_one_attached :file
  has_one_attached :image

  enum :purpose, {
    visual_method: "visual_method",
    qes_preparation: "qes_preparation",
    signature_field_appearance: "signature_field_appearance"
  }

  validates :page, numericality: { only_integer: true, greater_than: 0 }
  validates :x, :y, numericality: { greater_than_or_equal_to: 0 }
  validates :width, numericality: { greater_than: 0, less_than_or_equal_to: MAX_WIDTH }
  validates :height, numericality: { greater_than: 0, less_than_or_equal_to: MAX_HEIGHT }
  validates :text, length: { maximum: 500 }, allow_blank: true
  validate :text_or_image_present
  validate :acceptable_image_type

  def stamped_document
    return unless file.attached?

    Document.new(blob: file.blob)
  end

  def custom_text
    if qes_preparation?
      return text.to_s.delete_prefix(QES_MANDATORY_TEXT).strip
    end

    if signature_field_appearance?
      if text.to_s.start_with?("#{PADES_VISUAL_SIGNATURE_BY_PREFIX}\n")
        return text.to_s.delete_prefix("#{PADES_VISUAL_SIGNATURE_BY_PREFIX}\n").strip
      end

      if text.to_s.start_with?("#{PADES_VISUAL_SIGNATURE_BY_PREFIX} ")
        return text.to_s.delete_prefix("#{PADES_VISUAL_SIGNATURE_BY_PREFIX} ").strip
      end

      return "" if text.to_s == PADES_VISUAL_SIGNATURE_TEXT

      lines = text.to_s.split("\n")

      if lines.first == "Electronically signed" && lines.last == "Validate signatures in a PDF viewer or trusted validator."
        return lines[1...-1].join("\n").strip
      end
    end

    text.to_s
  end

  def self.pades_visible_signature_text(custom_text = nil)
    custom_text = custom_text.to_s.strip
    return PADES_VISUAL_SIGNATURE_TEXT if custom_text.blank?

    [ PADES_VISUAL_SIGNATURE_BY_PREFIX, custom_text ].join("\n")
  end

  private

  def text_or_image_present
    return if text.present? || image.attached?

    errors.add(:base, "Stamp text or image is required")
  end

  def acceptable_image_type
    return unless image.attached?
    return if image.blob.content_type.in?(%w[image/png image/jpeg])

    errors.add(:image, "must be a PNG or JPEG image")
  end
end
