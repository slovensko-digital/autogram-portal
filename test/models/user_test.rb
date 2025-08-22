# == Schema Information
#
# Table name: users
#
#  id                   :bigint           not null, primary key
#  api_token_public_key :string
#  email                :string
#  name                 :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
require "test_helper"

class UserTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
