# == Schema Information
#
# Table name: paper_signature_pages
#
#  id                 :bigint           not null, primary key
#  position           :integer          not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  paper_signature_id :bigint           not null
#
# Indexes
#
#  index_paper_signature_pages_on_paper_signature_id  (paper_signature_id)
#
# Foreign Keys
#
#  fk_rails_...  (paper_signature_id => paper_signatures.id)
#
# A photo of one signed page, or a PDF scan of the whole document, collected while its paper
# signature is a draft. Submitting combines the pages into the scan of the paper signature.
class PaperSignaturePage < ApplicationRecord
  belongs_to :paper_signature
  has_one_attached :file

  def image?
    PaperScan::IMAGE_TYPES.include?(file.content_type)
  end

  def pdf?
    file.content_type == PaperScan::PDF_TYPE
  end
end
