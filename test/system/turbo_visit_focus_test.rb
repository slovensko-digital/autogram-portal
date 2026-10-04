require "application_system_test_case"

class TurboVisitFocusTest < ApplicationSystemTestCase
  test "a Turbo Drive visit moves focus to the heading of the new page" do
    visit about_index_path
    assert_equal "BODY", page.evaluate_script("document.activeElement.tagName")

    find_link(I18n.t("header.links.docs"), match: :first).send_keys(:enter)
    assert_selector "h1", text: I18n.t("docs.index.header.title")

    assert_equal "H1", page.evaluate_script("document.activeElement.tagName")
    assert page.evaluate_script("document.getElementById('main-content').contains(document.activeElement)")
    assert_equal I18n.t("docs.index.header.title"), page.evaluate_script("document.activeElement.textContent").strip
  end

  test "a Turbo Drive visit keeps focus on an autofocused field" do
    visit about_index_path
    page.execute_script("Turbo.visit(#{new_user_confirmation_path.to_json})")
    assert_current_path new_user_confirmation_path

    assert_equal "user_email", page.evaluate_script("document.activeElement.id")
  end
end
