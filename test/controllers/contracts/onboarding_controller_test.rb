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

  test "qscd check offers slovak, czech and commercial devices" do
    contract = create_contract_without_session

    get "/contracts/#{contract.uuid}/onboarding/qscd_check", params: { method: "electronic", iframe: "true" }

    assert_response :success
    User::QSCD_GROUPS.values.flatten.each do |qscd|
      assert_select "input[type=radio][name=qscd][value='#{qscd}']"
    end
    assert_select "input[type=radio][name=qscd]:checked", count: 0
  end

  test "qscd check preselects the current choice and expands its group" do
    contract = create_contract_without_session

    get "/contracts/#{contract.uuid}/onboarding/qscd_check", params: { method: "electronic", qscd: "monet_proid", review: "true" }

    assert_response :success
    assert_select "input[type=radio][name=qscd][value='monet_proid'][checked]"
    assert_select "[data-toggle-collapsed-value='false'] input[value='monet_proid']"
    assert_select "[data-toggle-collapsed-value='true'] input[value='cz_eid_2018']"
  end

  test "qscd check exposes accessible names, groups and disclosure state" do
    contract = create_contract_without_session

    get "/contracts/#{contract.uuid}/onboarding/qscd_check", params: { method: "electronic", qscd: "cz_eid_2018", review: "true" }

    assert_response :success

    radio = css_select("input[type=radio][value='cz_eid_2018']").first
    assert_equal "required", radio["required"]
    assert_select "[id='#{radio['aria-labelledby']}']", text: I18n.t("qscd.title.cz_eid_2018")
    described = radio["aria-describedby"].split
    assert_select "[id='#{described.first}']", text: I18n.t("qscd.description.cz_eid_2018")
    assert_select "[id='#{described.last}']", text: /#{Regexp.escape(I18n.t("qscd.badges.certificate"))}/

    assert_select "h2 > button[aria-expanded='true'][aria-controls='qscd_group_cz_eid_content']"
    assert_select "h2 > button[aria-expanded='false'][aria-controls='qscd_group_tokens_content']"
    assert_select "#qscd_group_cz_eid_content[role=group][aria-labelledby='qscd_group_cz_eid_title']"
    assert_select "[role=group][aria-labelledby='qscd_group_sk_eid_title'] input[value='eid_2024']"
  end

  test "legacy czech id card goes to the legacy step" do
    contract = create_contract_without_session

    patch "/contracts/#{contract.uuid}/onboarding/qscd_check", params: { method: "electronic", qscd: "cz_eid_2012", iframe: "true" }

    assert_redirect_preserves_qscd(
      response.location,
      "/contracts/#{contract.uuid}/onboarding/legacy_eid_card",
      { "method" => "electronic", "qscd" => "cz_eid_2012", "iframe" => "true" }
    )

    get response.location

    assert_response :success
    assert_includes response.body, I18n.t("contracts.onboarding.legacy_eid_card.cz.warning_title")
  end

  test "pin and certificate steps use copy for the selected device" do
    contract = create_contract_without_session

    get "/contracts/#{contract.uuid}/onboarding/pin_check", params: { method: "electronic", qscd: "ica_securestore" }
    assert_includes response.body, I18n.t("contracts.onboarding.pin_check.token.title")
    assert_not_includes response.body, I18n.t("contracts.onboarding.pin_check.title")

    get "/contracts/#{contract.uuid}/onboarding/certificate_check", params: { method: "electronic", qscd: "cz_eid_2018" }
    assert_includes response.body, I18n.t("contracts.onboarding.certificate_check.cz.title")

    get "/contracts/#{contract.uuid}/onboarding/pin_check", params: { method: "electronic", qscd: "dpb_2023" }
    assert_includes response.body, I18n.t("contracts.onboarding.pin_check.title")
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
