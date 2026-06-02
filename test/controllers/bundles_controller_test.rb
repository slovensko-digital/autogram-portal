require "test_helper"

class BundlesControllerTest < ActionController::TestCase
  setup do
    @author = users(:one)
    @author.update_column(:email, "owner@example.com")
    author = @author
    @controller.singleton_class.define_method(:current_user) { author }
    @controller.singleton_class.define_method(:user_signed_in?) { true }
  end

  test "author bundle sign route offers autogram batch signing for multiple qes contracts" do
    bundle = create_bundle_with_contracts(author: @author, count: 2)

    get :sign, params: { id: bundle.uuid }

    assert_response :success
    author_proxy = bundle.recipients.active.author_proxies.find_by!(user: @author)

    assert_select "a[href='#{autogram_batch_bundle_path(bundle, recipient: author_proxy.uuid)}']"
    assert_equal 1, bundle.recipients.active.author_proxies.where(user: @author).count
  end

  private

  def create_bundle_with_contracts(author:, count:)
    contracts = count.times.map do |index|
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("%PDF-1.4 test content #{index}"),
        filename: "bundle-contract-#{index}.pdf",
        content_type: "application/pdf"
      )

      Contract.create!(
        allowed_methods: [ "qes" ],
        documents_attributes: [ { blob: blob } ],
        signature_parameters_attributes: {
          level: "BASELINE_B",
          format: "PAdES"
        }
      )
    end

    Bundle.create!(author: author, contracts: contracts)
  end
end
