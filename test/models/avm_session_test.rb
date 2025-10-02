# == Schema Information
#
# Table name: avm_sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  encryption_key     :string
#  error_message      :text
#  signing_started_at :datetime
#  status             :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  contract_id        :bigint           not null
#  document_id        :string
#
# Indexes
#
#  index_avm_sessions_on_contract_id  (contract_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#
require "test_helper"

class AvmSessionTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
