# == Schema Information
#
# Table name: signing_files
#
#  id          :bigint           not null, primary key
#  remote_hash :string
#  url         :string
#  uuid        :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  document_id :bigint           not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_signing_files_on_document_id  (document_id)
#  index_signing_files_on_user_id      (user_id)
#  index_signing_files_on_uuid         (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (document_id => documents.id)
#  fk_rails_...  (user_id => users.id)
#
class SigningFile < ApplicationRecord
  belongs_to :user
  belongs_to :document

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
end
