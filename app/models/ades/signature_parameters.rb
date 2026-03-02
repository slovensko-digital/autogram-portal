# == Schema Information
#
# Table name: ades_signature_parameters
#
#  id                    :bigint           not null, primary key
#  add_content_timestamp :boolean
#  container             :string
#  en319132              :boolean
#  format                :string
#  level                 :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  contract_id           :bigint           not null
#
# Indexes
#
#  index_ades_signature_parameters_on_contract_id  (contract_id)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#
module Ades
  class SignatureParameters < ApplicationRecord
    belongs_to :contract

    after_initialize :set_defaults, if: :new_record?
    before_validation :set_container

    validates :format, inclusion: { in: ->(record) { record.available_formats } }
    validates :level, presence: true, inclusion: { in: %w[BASELINE_B BASELINE_T BASELINE_LT BASELINE_LTA] }
    validates :container, inclusion: { in: [ "ASiC_E" ] }, if: -> { format.in?([ "XAdES", "CAdES" ]) }
    validates :container, absence: true, if: -> { format == "PAdES" }
    validates :en319132, inclusion: { in: [ true, false ] }
    validates :add_content_timestamp, inclusion: { in: [ true, false ] }

    def available_formats
      # TODO: handle case with multiple documents with xades/cades signatures without container
      return [ "XAdES", "CAdES" ] if contract.documents.size > 1

      document = contract.documents.first
      unless document.has_signatures?
        return [ document.is_pdf? ? "PAdES" : nil, "XAdES", "CAdES" ].compact
      end

      result = document.validation_result.document_info
      case [ result[:signature_form], result[:container_type] ]
      when [ "PAdES", nil ]
        [ "PAdES" ]
      when [ "XAdES", "ASiC_E" ]
        [ "XAdES" ]
      when [ "CAdES", "ASiC_E" ]
        [ "CAdES" ]
      else
        []
      end
    end

    private

    def set_defaults
      self.level ||= "BASELINE_B"
      self.en319132 = false if self.en319132.nil?
      self.add_content_timestamp = false if self.add_content_timestamp.nil?

      self.format ||= available_formats.first
      set_container
    end

    def set_container
      self.container = "ASiC_E" if format.in?([ "XAdES", "CAdES" ])
      self.container = nil if format == "PAdES"
    end
  end
end
