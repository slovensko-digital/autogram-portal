require "test_helper"

class HowToSignControllerTest < ActionDispatch::IntegrationTest
  test "the guide is public and linked from the menu" do
    get how_to_sign_index_path

    assert_response :success
    assert_select "h1", text: I18n.t("how_to_sign.index.header.title")
    assert_select "section#guide h3", text: I18n.t("how_to_sign.index.guide.send.title")
    assert_select "section#guide ol li", count: 8
    assert_select "a[href=?][aria-current=page]", how_to_sign_index_path, minimum: 1
  end

  test "the guide embeds the video with a link to its text version" do
    get how_to_sign_index_path

    assert_select "figure video[controls][aria-label=?]", I18n.t("how_to_sign.index.video.title") do
      assert_select "source[src=?][type='video/mp4']", "https://static-ssd.s3.eu-central-1.amazonaws.com/agp.mp4"
    end
    assert_select "figcaption a[href='#guide']"
  end
end
