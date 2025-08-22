# == Schema Information
#
# Table name: ades_xdc_properties
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
#  signing_parameter_id                              :bigint           not null
#
# Indexes
#
#  index_ades_xdc_properties_on_signing_parameter_id  (signing_parameter_id)
#
# Foreign Keys
#
#  fk_rails_...  (signing_parameter_id => ades_signing_parameters.id)
#
module Ades
  class XdcProperties < ApplicationRecord
    belongs_to :signing_parameter, class_name: "Ades::SigningParameter"
  end
end
