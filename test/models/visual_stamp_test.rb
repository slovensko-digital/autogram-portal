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
  test "requires stamp text or image" do
    stamp = VisualStamp.new(
      purpose: "qes_preparation",
      page: 1,
      x: 10,
      y: 20,
      width: 160,
      height: 48
    )

    assert_not stamp.valid?
    assert stamp.errors[:base].any?
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

  test "validates maximum visual stamp size" do
    stamp = VisualStamp.new(
      purpose: "visual_method",
      page: 1,
      x: 0,
      y: 0,
      width: VisualStamp::MAX_WIDTH + 1,
      height: VisualStamp::MAX_HEIGHT + 1,
      text: "Too large"
    )

    assert_not stamp.valid?
    assert stamp.errors[:width].any?
    assert stamp.errors[:height].any?
  end

  test "builds pades visible signature text on separate lines" do
    assert_equal "Electronically signed by\nMarek Celuch", VisualStamp.pades_visible_signature_text("Marek Celuch")
    assert_equal "Electronically signed", VisualStamp.pades_visible_signature_text(nil)
  end

  test "extracts editable custom text from newline pades visible signature text" do
    stamp = VisualStamp.new(
      purpose: "signature_field_appearance",
      page: 1,
      x: 0,
      y: 0,
      width: 180,
      height: 64,
      text: "Electronically signed by\nMarek Celuch"
    )

    assert_equal "Marek Celuch", stamp.custom_text
  end
end
