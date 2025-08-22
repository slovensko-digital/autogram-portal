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
require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
