require "test_helper"

class ErrorPagesTest < ActionDispatch::IntegrationTest
  test "error pages are translated and link back to the portal" do
    get "/404"

    assert_response :not_found
    assert_select "html[lang='sk']"
    assert_select "title", text: "#{I18n.t('error_pages.not_found.title', locale: :sk)} – Autogram Portal"
    assert_select "h1", count: 1, text: I18n.t("error_pages.not_found.title", locale: :sk)
    assert_select "main a[href='/']", text: I18n.t("error_pages.home", locale: :sk)
    assert_select "a[href=?]", "mailto:#{Rails.application.config.footer[:support_email]}"
    assert_no_match(/application owner|check the logs/i, response.body)
  end

  test "error pages use the visitor's language" do
    cookies[:locale] = "en"

    get "/500"

    assert_response :internal_server_error
    assert_select "html[lang='en']"
    assert_select "h1", text: I18n.t("error_pages.internal_server_error.title", locale: :en)
  end

  test "statuses without their own text use the generic page" do
    post "/405"

    assert_response :method_not_allowed
    assert_select "h1", text: I18n.t("error_pages.generic.title", locale: :sk)
    assert_select "p", text: I18n.t("error_pages.code", code: 405, locale: :sk)
  end

  test "json requests get a json error" do
    get "/404", as: :json

    assert_response :not_found
    assert_equal({ "error" => "Not Found" }, response.parsed_body)
  end

  test "unknown addresses render the error page through the exceptions app" do
    env_config = Rails.application.env_config
    previous = env_config.slice("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
    env_config["action_dispatch.show_exceptions"] = :all
    env_config["action_dispatch.show_detailed_exceptions"] = false

    get "/neexistujuca-stranka"

    assert_response :not_found
    assert_select "h1", text: I18n.t("error_pages.not_found.title", locale: :sk)
  ensure
    env_config.merge!(previous)
  end

  test "missing records render the translated not found page" do
    get contract_path(SecureRandom.uuid)

    assert_response :not_found
    assert_select "h1", text: I18n.t("error_pages.not_found.title", locale: :sk)
    assert_select "main a[href='/']"
  end
end
