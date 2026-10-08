require "test_helper"
require_relative "../support/signing_flow_helper"
require_relative "../support/plan_limits_helper"

class RetentionNoticesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include SigningFlowHelper
  include PlanLimitsHelper

  setup do
    @user = confirmed_user("basic@example.com")
    @tenant = @user.tenants.sole
    sign_in @user
  end

  test "document detail shows when the retention of the plan deletes it" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60") do
      contract = create_contract(created_at: 10.days.ago)

      get contract_path(contract)

      assert_response :success
      assert_includes response.body, I18n.t("retention.notice.title.document",
        date: contract.scheduled_deletion_at.strftime("%d.%m.%Y"),
        countdown: I18n.t("retention.countdown.days", count: 50))
    end
  end

  test "bundle detail shows that the bundle is deleted soon" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60") do
      bundle = create_bundle("Zmluva o dielo", created_at: 57.days.ago)

      get bundle_path(bundle)

      assert_response :success
      assert_select "p", text: I18n.t("retention.notice.title.bundle",
        date: bundle.scheduled_deletion_at.strftime("%d.%m.%Y"),
        countdown: I18n.t("retention.countdown.days", count: 3))
    end
  end

  test "lists mark the documents deleted soon" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60") do
      create_bundle("Starý balík", created_at: 59.days.ago)
      create_bundle("Nový balík", created_at: 1.day.ago)
      create_contract(created_at: 60.days.ago + 1.hour)

      get bundles_path

      assert_response :success
      assert_includes response.body, I18n.t("retention.note", plan: "Basic", count: 60)
      assert_select "span", text: I18n.t("retention.badge", countdown: I18n.t("retention.countdown.tomorrow")), count: 1

      get contracts_path

      assert_response :success
      assert_select "span", text: I18n.t("retention.badge", countdown: I18n.t("retention.countdown.today")), count: 1
    end
  end

  test "home links to the list of the documents deleted within a week" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60") do
      create_bundle("Starý balík", created_at: 55.days.ago)
      create_bundle("Nový balík", created_at: 1.day.ago)

      get dashboard_path

      assert_response :success
      assert_select "a[href=?]", bundles_path(sort: "oldest"), text: I18n.t("dashboard.expiring_documents.title", count: 1)
    end
  end

  test "home links to both lists when standalone and bundled documents are deleted soon" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60") do
      create_bundle("Starý balík", created_at: 55.days.ago)
      create_contract(created_at: 58.days.ago)
      create_contract(created_at: 57.days.ago)

      get dashboard_path

      assert_response :success
      assert_includes response.body, I18n.t("dashboard.expiring_documents.title", count: 3)
      assert_select "a[href=?]", contracts_path(sort: "oldest"), text: I18n.t("header.links.contracts")
      assert_select "a[href=?]", bundles_path(sort: "oldest"), text: I18n.t("header.links.bundles")
    end
  end

  test "plans that keep documents show no retention notices" do
    with_plan_limits("BASIC_RETENTION_DAYS" => nil) do
      bundle = create_bundle("Starý balík", created_at: 1.year.ago)
      contract = create_contract(created_at: 1.year.ago)

      [ dashboard_path, bundles_path, contracts_path, bundle_path(bundle), contract_path(contract), new_contract_path ].each do |path|
        get path

        assert_response :success
        assert_no_match(/automaticky (mažú|zmaž)|Zmaže sa/, response.body)
      end
    end
  end

  private

  def create_contract(created_at:)
    Contract.create!(tenant: @tenant, documents: [ Document.new(blob: pdf_blob) ], created_at: created_at)
  end

  def create_bundle(name, created_at:)
    contract = Contract.create!(tenant: @tenant, documents: [ Document.new(blob: pdf_blob("#{name}.pdf")) ], created_at: created_at)
    Bundle.create!(tenant: @tenant, name: name, contracts: [ contract ], created_at: created_at)
  end
end
