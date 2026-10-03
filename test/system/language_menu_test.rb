require "application_system_test_case"

class LanguageMenuTest < ApplicationSystemTestCase
  test "escape inside the open language menu closes it and returns focus to its button" do
    visit about_index_path

    button = find("button[aria-controls='language-menu']")
    button.click
    assert_selector "#language-menu", visible: true
    assert_equal "true", button["aria-expanded"]

    button.send_keys(:tab)
    assert page.evaluate_script("document.getElementById('language-menu').contains(document.activeElement)"),
           "Tab from the open menu button should move into the menu"

    page.send_keys(:escape)
    assert_no_selector "#language-menu", visible: true
    assert_equal "false", button["aria-expanded"]
    assert_equal "language-menu", page.evaluate_script("document.activeElement.getAttribute('aria-controls')")
  end
end
