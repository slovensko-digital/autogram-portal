# == Schema Information
#
# Table name: documents
#
#  id          :bigint           not null, primary key
#  remote_hash :string
#  url         :string
#  uuid        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  contract_id :bigint
#
# Indexes
#
#  index_documents_on_contract_id  (contract_id)
#  index_documents_on_uuid         (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (contract_id => contracts.id)
#
require "test_helper"

class DocumentTest < ActiveSupport::TestCase
  test "available extension target levels include timestamp and archive for baseline signatures" do
    document = build_document_with_signature_levels("BASELINE_B")

    assert_equal %w[T LTA], document.available_extension_target_levels
    assert document.extendable_signatures?(target_level: "T")
    assert document.extendable_signatures?(target_level: "LTA")
  end

  test "available extension target levels only include archive for timestamped signatures" do
    document = build_document_with_signatures(
      { signature_level: "BASELINE_T", timestamp_info: { qualified: true } }
    )

    assert_equal [ "LTA" ], document.available_extension_target_levels
    assert_not document.extendable_signatures?(target_level: "T")
    assert document.extendable_signatures?(target_level: "LTA")
  end

  test "timestamp extension is unavailable when signatures already have timestamps even at lower baseline level" do
    document = build_document_with_signatures(
      { signature_level: "BASELINE_B", timestamp_info: { qualified: true } }
    )

    assert_equal [ "LTA" ], document.available_extension_target_levels
    assert_not document.extendable_signatures?(target_level: "T")
    assert document.extendable_signatures?(target_level: "LTA")
  end

  private

  def build_document_with_signature_levels(*levels)
    build_document_with_signatures(*levels.map { |level| { signature_level: level } })
  end

  def build_document_with_signatures(*signatures)
    validation_result = AutogramService::ValidationResult.new(
      has_signatures: true,
      signatures: signatures
    )

    Document.new.tap do |document|
      document.define_singleton_method(:validation_result) { validation_result }
    end
  end
end
