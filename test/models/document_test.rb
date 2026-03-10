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
#
# Indexes
#
#  index_documents_on_contract_id  (contract_id)
#  index_documents_on_uuid         (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#
require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
