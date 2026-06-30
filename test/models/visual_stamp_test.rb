# == Schema Information
#
# Table name: visual_stamps
#
#  id                 :bigint           not null, primary key
#  height             :decimal(10, 2)   not null
#  page               :integer          default(1), not null
#  purpose            :string           not null
#  text               :text
#  width              :decimal(10, 2)   not null
#  x                  :decimal(10, 2)   not null
#  y                  :decimal(10, 2)   not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  document_id        :bigint           not null
#  signer_contract_id :bigint           not null
#
# Indexes
#
#  idx_on_signer_contract_id_document_id_purpose_d86ba1c031  (signer_contract_id,document_id,purpose)
#  index_visual_stamps_on_document_id                        (document_id)
#  index_visual_stamps_on_signer_contract_id                 (signer_contract_id)
#
# Foreign Keys
#
#  fk_rails_...  (document_id => documents.id)
#  fk_rails_...  (signer_contract_id => signer_contracts.id)
#
require "test_helper"

class VisualStampTest < ActiveSupport::TestCase
  test "defaults stamp text" do
    stamp = VisualStamp.new(
      purpose: "qes_preparation",
      page: 1,
      x: 10,
      y: 20,
      width: 160,
      height: 48
    )

    stamp.valid?

    assert_equal VisualStamp::DEFAULT_TEXT, stamp.text
  end

  test "validates positive placement" do
    stamp = VisualStamp.new(
      purpose: "visual_method",
      page: 0,
      x: -1,
      y: 0,
      width: 0,
      height: 48
    )

    assert_not stamp.valid?
    assert stamp.errors[:page].any?
    assert stamp.errors[:x].any?
    assert stamp.errors[:width].any?
  end
end
