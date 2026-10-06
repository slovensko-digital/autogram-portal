require "test_helper"

class TenantsHelperTest < ActionView::TestCase
  test "archive action is labeled as an archive timestamp without the archivation feature" do
    I18n.with_locale(:sk) do
      assert_equal "Pridať archívnu pečiatku", archive_action_t(tenants(:one), "documents.new.actions.archive.title")
      assert_equal "Pridať archívnu pečiatku k podpisom", archive_action_t(nil, "contracts.signature_extension.levels.lta.button")
    end
  end

  test "archive action keeps archive document label with the archivation feature" do
    tenant = tenants(:one)
    tenant.features = [ "archivation" ]

    I18n.with_locale(:sk) do
      assert_equal "Archivovať dokument", archive_action_t(tenant, "documents.new.actions.archive.title")
      assert_equal "Archivovať podpísaný dokument", archive_action_t(tenant, "contracts.signature_extension.levels.lta.button")
    end
  end

  test "labels without an archivation variant are shared" do
    I18n.with_locale(:sk) do
      assert_equal "Pridať časovú pečiatku", archive_action_t(tenants(:one), "contracts.signature_extension.levels.t.title")
    end
  end
end
