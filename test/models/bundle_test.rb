# == Schema Information
#
# Table name: bundles
#
#  id         :bigint           not null, primary key
#  note       :text
#  uuid       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_bundles_on_user_id  (user_id)
#  index_bundles_on_uuid     (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class BundleTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
