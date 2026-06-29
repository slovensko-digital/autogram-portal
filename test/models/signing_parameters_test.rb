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
  test "signed pades document keeps pades as the only available format" do
    contract = Contract.new
    validation_result = AutogramService::ValidationResult.new(
      hasSignatures: true,
      documentInfo: {
        signatureForm: "PAdES",
        containerType: nil
      }
    )

    document = Document.new
    document.define_singleton_method(:has_signatures?) { true }
    document.define_singleton_method(:validation_result) { validation_result }

    contract.define_singleton_method(:documents) { [ document ] }

    signature_parameters = Ades::SignatureParameters.new(
      contract: contract,
      level: "BASELINE_B"
    )

    assert_equal [ "PAdES" ], signature_parameters.available_formats
    assert_equal "PAdES", signature_parameters.format
    assert signature_parameters.valid?, signature_parameters.errors.full_messages.to_sentence
  end
end
