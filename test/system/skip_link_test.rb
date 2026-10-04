require "application_system_test_case"

class SkipLinkTest < ApplicationSystemTestCase
  test "skip link moves focus to the main content repeatedly and after Turbo navigation" do
    visit about_index_path
    find("body").send_keys(:tab)
    assert_equal I18n.t("layouts.skip_to_main_content"), active_element_text

    click_link I18n.t("header.links.docs")
    assert_selector "h1", text: I18n.t("docs.index.header.title")
    click_link I18n.t("header.links.about")
    assert_current_path about_index_path
    assert_selector "#main-content h1:focus"

    3.times do
      page.execute_script("document.querySelector('a[href=\"#main-content\"]').focus()")
      page.send_keys(:enter)
      assert_equal "main-content", page.evaluate_script("document.activeElement.id")
      assert_equal "solid", page.evaluate_script("getComputedStyle(document.getElementById('main-content')).outlineStyle"),
                   "Focused main content should show its focus outline"

      page.send_keys(:tab)
      assert page.evaluate_script("document.getElementById('main-content').contains(document.activeElement)"),
             "Tab after skipping should stay in the main content, got #{active_element_text.inspect}"
    end
  end

  private

  def active_element_text
    page.evaluate_script("document.activeElement.textContent").strip
  end
end
