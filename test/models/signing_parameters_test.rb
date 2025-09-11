# == Schema Information
#
# Table name: ades_signature_parameters
#
#  id                       :bigint           not null, primary key
#  container                :string
#  level                    :string
#  signature_baseline_level :string
#  signature_form           :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
require "test_helper"

class Ades::SignatureParametersTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
