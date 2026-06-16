require "test_helper"

class Contracts::OnboardingControllerTest < ActionDispatch::IntegrationTest
  test "anonymous iframe electronic onboarding keeps qscd in redirect chain" do
    contract = create_contract_without_session

    patch "/contracts/#{contract.uuid}/onboarding/qscd_check", params: {
      method: "electronic",
      qscd: "eid_2024",
      iframe: "true"
    }

    assert_redirect_preserves_qscd(
      response.location,
      "/contracts/#{contract.uuid}/onboarding/pin_check",
      { "method" => "electronic", "qscd" => "eid_2024", "iframe" => "true" }
    )

    patch "/contracts/#{contract.uuid}/onboarding/pin_check", params: {
      method: "electronic",
      qscd: "eid_2024",
      iframe: "true"
    }

    assert_redirect_preserves_qscd(
      response.location,
      "/contracts/#{contract.uuid}/onboarding/certificate_check",
      { "method" => "electronic", "qscd" => "eid_2024", "iframe" => "true" }
    )

    patch "/contracts/#{contract.uuid}/onboarding/certificate_check", params: {
      method: "electronic",
      qscd: "eid_2024",
      iframe: "true"
    }

    assert_redirect_preserves_qscd(
      response.location,
      "/contracts/#{contract.uuid}/signature_apps",
      { "qscd" => "eid_2024", "iframe" => "true" }
    )
  end

  test "pin and certificate steps keep qscd in iframe forms" do
    contract = create_contract_without_session

    get "/contracts/#{contract.uuid}/onboarding/pin_check", params: {
      method: "electronic",
      qscd: "eid_2024",
      iframe: "true"
    }

    assert_response :success
    assert_select "input[type=hidden][name=qscd][value='eid_2024']"
    assert_select "a[href*='qscd=eid_2024']"

    get "/contracts/#{contract.uuid}/onboarding/certificate_check", params: {
      method: "electronic",
      qscd: "eid_2024",
      iframe: "true"
    }

    assert_response :success
    assert_select "input[type=hidden][name=qscd][value='eid_2024']"
    assert_select "a[href*='qscd=eid_2024']"
  end

  private

  def assert_redirect_preserves_qscd(location, expected_path, expected_query)
    uri = URI.parse(location)

    assert_equal expected_path, uri.path
    assert_equal expected_query, Rack::Utils.parse_nested_query(uri.query)
  end

  def create_contract_without_session
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("%PDF-1.4 test content"),
      filename: "onboarding-test.pdf",
      content_type: "application/pdf"
    )

    contract = Contract.new(
      documents_attributes: [ { blob: blob } ],
      signature_parameters_attributes: {
        level: "BASELINE_B",
        format: "PAdES"
      }
    )
    contract.save!

    contract
  end
end
