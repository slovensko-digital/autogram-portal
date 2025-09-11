# == Schema Information
#
# Table name: documents
#
#  id          :bigint           not null, primary key
#  remote_hash :string
#  url         :string
#  uuid        :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  contract_id :bigint
#  user_id     :bigint           not null
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
  belongs_to :user
  belongs_to :contract, optional: true

  has_one :xdc_parameters, class_name: "XdcParameters", dependent: :destroy
  has_one_attached :blob

  def filename
    blob.attached? ? blob.filename.to_s : nil
  end

  def content
    blob.attached? ? blob.download : nil
  end

  def content_type
    blob.attached? ? blob.content_type : nil
  end

  def validate_signatures
    AutogramService.validate_signatures(self)
  end

  def has_signatures?
    validate_signatures.has_signatures
  end

  def visualize
    AutogramService.visualize_document(self)
  end
end
