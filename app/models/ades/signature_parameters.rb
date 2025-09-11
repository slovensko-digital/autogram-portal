# == Schema Information
#
# Table name: ades_signature_parameters
#
#  id                       :bigint           not null, primary key
#  add_content_timestamp    :boolean
#  container                :string
#  en319132                 :boolean
#  level                    :string
#  signature_baseline_level :string
#  signature_form           :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
module Ades
  class SignatureParameters < ApplicationRecord
    belongs_to :contract
  end
end
