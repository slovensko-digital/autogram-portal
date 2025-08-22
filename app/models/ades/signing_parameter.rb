# == Schema Information
#
# Table name: ades_signing_parameters
#
#  id                       :bigint           not null, primary key
#  container                :string
#  level                    :string
#  signature_baseline_level :string
#  signature_form           :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
module Ades
  class SigningParameter < ApplicationRecord
    belongs_to :document

    has_one :xdc_properties, class_name: "Ades::XdcProperties", dependent: :destroy
  end
end
