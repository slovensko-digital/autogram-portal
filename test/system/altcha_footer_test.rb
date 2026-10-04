require "application_system_test_case"

class AltchaFooterTest < ApplicationSystemTestCase
  test "captcha footer keeps full opacity and names its external link" do
    visit new_user_confirmation_path

    footer = find("altcha-widget .altcha-footer")
    assert_equal "1", page.evaluate_script("getComputedStyle(document.querySelector('altcha-widget .altcha-footer')).opacity")
    assert_text I18n.t("devise.shared.captcha.captcha_footer_html", link_label: "").then { |html| Nokogiri::HTML.fragment(html).text }
    assert_equal I18n.t("devise.shared.captcha.captcha_link_label"), footer.find("a[href='https://altcha.org/']")["aria-label"]
  end
end
