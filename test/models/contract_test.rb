# == Schema Information
#
# Table name: contracts
#
#  id                           :bigint           not null, primary key
#  allowed_methods              :string           default(["qes"]), is an Array
#  author_notifications_enabled :boolean          default(FALSE), not null
#  temporary_storage_reason     :string
#  uuid                         :string           not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  bundle_id                    :bigint
#  user_id                      :bigint
#
# Indexes
#
#  index_contracts_on_bundle_id                 (bundle_id)
#  index_contracts_on_temporary_storage_reason  (temporary_storage_reason)
#  index_contracts_on_user_id                   (user_id)
#  index_contracts_on_uuid                      (uuid)
#
# Foreign Keys
#
#  fk_rails_...  (bundle_id => bundles.id)
#  fk_rails_...  (user_id => users.id)
#
require "test_helper"
require "tempfile"
require "zip"

class ContractTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "does not notify standalone contract author by default" do
    contract = Contract.new(user: @user)
    contract.define_singleton_method(:awaiting_signature?) { false }

    assert_not contract.should_notify_user?
  end

  test "notifies standalone contract author when enabled" do
    contract = Contract.new(user: @user, author_notifications_enabled: true)
    contract.define_singleton_method(:awaiting_signature?) { false }

    assert contract.should_notify_user?
  end

  test "does not notify author when signer is the author" do
    contract = Contract.new(user: @user, author_notifications_enabled: true)
    signer = Struct.new(:user).new(@user)
    contract.define_singleton_method(:awaiting_signature?) { false }

    assert_not contract.should_notify_user?(signer: signer)
  end

  test "expands uploaded asice container into contract documents and preserves signed container" do
    contract = Contract.new(
      user: @user,
      documents: [ Document.new(blob: asice_blob("container.asice", {
        "contract-a.txt" => "alpha",
        "nested/contract-b.txt" => "beta",
        "META-INF/signatures.xml" => "<signature/>"
      })) ]
    )

    assert contract.save, contract.errors.full_messages.to_sentence
    assert contract.signed_document.attached?
    assert_equal "container.asice", contract.signed_document.filename.to_s
    assert_equal ["contract-a.txt", "contract-b.txt"], contract.documents.map(&:filename).sort
    assert_equal "XAdES", contract.signature_parameters.format
  end

  test "expands pending uploaded asice container before the contract is saved" do
    uploaded_file = uploaded_asice_file("pending.asice", {
      "contract-a.txt" => "alpha",
      "mimetype" => "application/vnd.etsi.asic-e+zip",
      "document.xdcf" => "<xdcf></xdcf>",
      "nested/contract-b.pdf" => "%PDF-1.4 fake",
      "contract-b.txt" => "beta",
      "META-INF/signatures.xml" => "<signature/>"
    })

    contract = Contract.new(
      user: @user,
      documents: [ Document.new(blob: uploaded_file) ]
    )

    assert contract.save, contract.errors.full_messages.to_sentence
    assert contract.signed_document.attached?
    assert_equal "pending.asice", contract.signed_document.filename.to_s
    assert_equal ["contract-a.txt", "contract-b.pdf", "contract-b.txt", "document.xdcf"], contract.documents.map(&:filename).sort
    xdcf_document = contract.documents.find { |document| document.filename == "document.xdcf" }
    assert_equal "application/vnd.gov.sk.xmldatacontainer+xml", xdcf_document.content_type
    assert_predicate xdcf_document.xdc_parameters, :present?
  ensure
    uploaded_file&.tempfile&.close!
  end

  private

  def asice_blob(filename, entries)
    buffer = Zip::OutputStream.write_buffer do |zip|
      entries.each do |path, content|
        zip.put_next_entry(path)
        zip.write(content)
      end
    end

    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(buffer.string),
      filename: filename,
      content_type: "application/vnd.etsi.asic-e+zip"
    )
  end

  def uploaded_asice_file(filename, entries)
    buffer = Zip::OutputStream.write_buffer do |zip|
      entries.each do |path, content|
        zip.put_next_entry(path)
        zip.write(content)
      end
    end

    tempfile = Tempfile.new([File.basename(filename, ".asice"), ".asice"])
    tempfile.binmode
    tempfile.write(buffer.string)
    tempfile.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: tempfile,
      filename: filename,
      type: "application/vnd.etsi.asic-e+zip"
    )
  end
end
