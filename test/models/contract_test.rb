# == Schema Information
#
# Table name: contracts
#
#  id              :bigint           not null, primary key
#  allowed_methods :string           default(["qes"]), is an Array
#  uuid            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  bundle_id       :bigint
#  user_id         :bigint
#
# Indexes
#
#  index_contracts_on_bundle_id  (bundle_id)
#  index_contracts_on_user_id    (user_id)
#  index_contracts_on_uuid       (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"

class ContractTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
