require "application_system_test_case"

class DocsContentsTest < ApplicationSystemTestCase
  test "the table of contents of the user guide marks the section being read" do
    visit docs_path
    within "nav#docs-contents" do
      assert_selector "a[aria-current='true'][href='#documents-and-bundles']"
    end

    page.execute_script("document.getElementById('bundles').scrollIntoView()")
    within "nav#docs-contents" do
      assert_selector "a[aria-current='true'][href='#bundles']"
      assert_selector "a[aria-current='true']", count: 1
    end
  end

  test "keyboard users move between the contents and the sections of the user guide" do
    visit docs_path

    find("nav#docs-contents a[href='#signing']").send_keys(:enter)
    assert_equal "signing", active_element_id, "the contents link should move focus to its section"
    page.send_keys(:tab)
    assert page.evaluate_script("document.getElementById('signing').contains(document.activeElement)"),
           "Tab after the contents link should continue inside the section"

    find("#signing a[href='#docs-contents']").send_keys(:enter)
    assert_equal "docs-contents", active_element_id, "the back link should move focus to the contents"
    page.send_keys(:tab)
    assert_equal "#documents-and-bundles", page.evaluate_script("document.activeElement.getAttribute('href')")
  end

  private

  def active_element_id
    page.evaluate_script("document.activeElement.id")
  end
end
