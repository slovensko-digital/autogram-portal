# == Schema Information
#
# Table name: xdc_parameters
#
#  id                                                :bigint           not null, primary key
#  container_xmlns                                   :string
#  embed_used_schemas                                :boolean
#  fs_form_identifier                                :string
#  identifier                                        :string
#  schema                                            :text
#  schema_identifier                                 :string
#  schema_mime_type                                  :string
#  transformation                                    :text
#  transformation_identifier                         :string
#  transformation_language                           :string
#  transformation_media_destination_type_description :string
#  transformation_target_environment                 :string
#  created_at                                        :datetime         not null
#  updated_at                                        :datetime         not null
#  document_id                                       :bigint           not null
#
# Indexes
#
#  index_xdc_parameters_on_document_id  (document_id)
#
# Foreign Keys
#
#  fk_rails_...  (document_id => documents.id)
#
class XdcParameters < ApplicationRecord
  belongs_to :document
end
