# == Schema Information
#
# Table name: ades_xdc_parameters
#
#  id                                                :bigint           not null, primary key
#  auto_load_eform                                   :boolean
#  container_xmlns                                   :string
#  embed_used_schemas                                :boolean
#  identifier                                        :string
#  schema                                            :text
#  schema_identifier                                 :string
#  transformation                                    :text
#  transformation_identifier                         :string
#  transformation_language                           :string
#  transformation_media_destination_type_description :string
#  transformation_target_environment                 :string
#  created_at                                        :datetime         not null
#  updated_at                                        :datetime         not null
#  signature_parameter_id                              :bigint           not null
#
# Indexes
#
#  index_ades_xdc_parameters_on_signature_parameter_id  (signature_parameter_id)
#
# Foreign Keys
#
#  fk_rails_...  (signature_parameter_id => ades_signature_parameters.id)
#
require "test_helper"

class Ades::XdcParametersTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
