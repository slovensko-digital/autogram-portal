# == Schema Information
#
# Table name: documents
#
#  id              :bigint           not null, primary key
#  allowed_methods :string           default([]), is an Array
#  uuid            :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  bundle_id       :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_documents_on_bundle_id  (bundle_id)
#  index_documents_on_user_id    (user_id)
#  index_documents_on_uuid       (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (user_id => users.id)
#
class Document < ApplicationRecord
  belongs_to :user
  belongs_to :bundle

  has_one :file, class_name: "SigningFile", dependent: :destroy
  has_one :signing_parameter, class_name: "Ades::SigningParameter", dependent: :destroy
end
