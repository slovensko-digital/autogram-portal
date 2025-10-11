# == Schema Information
#
# Table name: identities
#
#  id         :bigint           not null, primary key
#  provider   :string           not null
#  uid        :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_identities_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
