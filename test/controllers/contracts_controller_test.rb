require "test_helper"

class ContractsControllerTest < ActionDispatch::IntegrationTest
  test "visual signing creates stamped content and marks signer signed" do
    with_allowed_methods(%w[visual]) do
      contract = create_pdf_contract(allowed_methods: [ "visual" ])
      stamp_service = fake_stamp_service("stamped visual pdf")

      with_autogram_service(stamp_service) do
        post "/contracts/#{contract.uuid}/visual_signing", params: {
          stamp: {
            page: 1,
            x: 120.5,
            y: 88.25,
            width: 200,
            height: 60,
            text: "Placed stamp"
          }
        }
      end

      assert_redirected_to sign_contract_path(contract)

      contract.reload
      signer_contract = contract.signer_contracts.last
      assert signer_contract.signed?
      assert_equal 1, contract.content_versions.count
      assert_equal "visual", contract.latest_content_version.origin
      assert_equal "stamped visual pdf", contract.latest_content_version.content

      visual_stamp = signer_contract.visual_stamps.visual_method.last
      assert_equal 120.5, visual_stamp.x.to_f
      assert_equal 88.25, visual_stamp.y.to_f
      assert_equal 200.0, visual_stamp.width.to_f
      assert_equal 60.0, visual_stamp.height.to_f
      assert_equal "Placed stamp", visual_stamp.text
      assert_equal({ page: 1, x: 120.5, y: 88.25, width: 200.0, height: 60.0, text: "Placed stamp" }, stamp_service.last_stamp)
    end
  end

  test "qes visual preparation stores prepared source without marking signer signed" do
    with_allowed_methods(%w[qes visual]) do
      contract = create_pdf_contract(allowed_methods: [ "qes", "visual" ])

      with_autogram_service(fake_stamp_service("prepared qes pdf")) do
        post "/contracts/#{contract.uuid}/visual_signing", params: { recipient: "", purpose: "qes_preparation" }
      end

      assert_redirected_to signature_apps_contract_path(contract)

      signer_contract = contract.signer_contracts.last
      assert_not signer_contract.signed?
      assert_equal 0, contract.content_versions.count
      assert_equal 1, signer_contract.visual_stamps.qes_preparation.count
      assert_equal "prepared qes pdf", signer_contract.visual_stamps.qes_preparation.last.file.download
    end
  end

  private

  def create_pdf_contract(allowed_methods:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "visual-test.pdf",
      content_type: "application/pdf"
    )

    Contract.create!(
      allowed_methods: allowed_methods,
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )
  end

  def fake_stamp_service(content)
    Struct.new(:content, :last_stamp) do
      def stamp_pdf(_document, stamp:)
        self.last_stamp = stamp
        content
      end
    end.new(content)
  end

  def with_autogram_service(fake_service)
    environment_singleton = AutogramEnvironment.singleton_class
    environment_singleton.send(:alias_method, :__original_autogram_service, :autogram_service)
    environment_singleton.send(:define_method, :autogram_service) { fake_service }

    yield
  ensure
    environment_singleton.send(:remove_method, :autogram_service)
    environment_singleton.send(:alias_method, :autogram_service, :__original_autogram_service)
    environment_singleton.send(:remove_method, :__original_autogram_service)
  end

  def with_allowed_methods(methods)
    original_allowed_methods = Contract::ALLOWED_METHODS
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, methods)

    yield
  ensure
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, original_allowed_methods)
  end
end
