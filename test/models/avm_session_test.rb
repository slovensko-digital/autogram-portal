# == Schema Information
#
# Table name: avm_sessions
#
#  id                 :bigint           not null, primary key
#  completed_at       :datetime
#  encryption_key     :string
#  error_message      :text
#  signing_started_at :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  document_id        :string
#
require "test_helper"

class AvmSessionTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
