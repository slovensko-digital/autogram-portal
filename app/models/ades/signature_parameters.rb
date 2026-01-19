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

    validates :format, presence: true, inclusion: { in: %w[PAdES XAdES CAdES] }
    validates :level, presence: true, inclusion: { in: %w[BASELINE_B BASELINE_T BASELINE_LT BASELINE_LTA] }
    validates :container, inclusion: { in: [ "ASiC_E" ] }, allow_nil: true
    validates :en319132, inclusion: { in: [ true, false ] }
    validates :add_content_timestamp, inclusion: { in: [ true, false ] }
    validate :validate_parameters_combination

    def format_container_combination
      case [ format, container ]
      when [ "PAdES", nil ]
        "pades"
      when [ "XAdES", "ASiC_E" ]
        "xades_asice"
      when [ "CAdES", "ASiC_E" ]
        "cades_asice"
      else
        throw "Invalid format/container combination: #{format}/#{container}"
      end
    end

    def format_container_combination=(combined_format)
      return if combined_format.nil?

      case combined_format
      when "pades"
        self.format = "PAdES"
        self.container = nil
      when "xades_asice"
        self.format = "XAdES"
        self.container = "ASiC_E"
      when "cades_asice"
        self.format = "CAdES"
        self.container = "ASiC_E"
      end
    end

    private

    def validate_parameters_combination
      if container
        errors.add(:container, "must not be ASiC_E when format is PAdES") unless %w[XAdES CAdES].include?(format)
      else
        errors.add(:container, "must be ASiC_E when format is XAdES or CAdES") if %w[XAdES CAdES].include?(format)
      end

      if format == "PAdES"
        errors.add(:format, "must not be PAdES when signing multiuple documents (container ASiC_E is required)") if contract.documents.size > 1
        errors.add(:format, "must not be PAdES when document is not PDF") if contract.documents.any? { |d| !d.is_pdf? }
      end
    end

    def set_defaults
      self.level ||= "BASELINE_B"
      self.format ||= "PAdES"
      self.container ||= nil
      self.en319132 = false if self.en319132.nil?
      self.add_content_timestamp = false if self.add_content_timestamp.nil?
    end
  end
end
