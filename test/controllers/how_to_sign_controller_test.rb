require "test_helper"

class HowToSignControllerTest < ActionDispatch::IntegrationTest
  test "the guide is public and linked from the menu" do
    get how_to_sign_index_path

    assert_response :success
    assert_select "h1", text: "#{I18n.t("how_to_sign.index.header.title")} #{I18n.t("how_to_sign.index.header.title_highlight")}"
    assert_select "section#guide h3", text: I18n.t("how_to_sign.index.guide.send.title")
    assert_select "section#guide ol li", count: 9
    assert_select "nav[aria-labelledby=how-to-sign-contents] a[href=?]", "#send", text: I18n.t("how_to_sign.index.contents.send")
    assert_select "#send h4", text: I18n.t("how_to_sign.index.guide.send.steps.email.title")
    assert_select "a[href=?][aria-current=page]", how_to_sign_index_path, minimum: 1
  end

  test "the contents link to every part of the guide and mark the video as current" do
    get how_to_sign_index_path

    assert_select "nav[aria-labelledby=how-to-sign-contents]" do
      assert_select "a[aria-current=true][href='#video']", text: I18n.t("how_to_sign.index.contents.video")
      %w[send sign eid received validate apps].each do |anchor|
        assert_select "a[href=?]", "##{anchor}", text: I18n.t("how_to_sign.index.contents.#{anchor}")
      end
    end
    %w[video send sign eid received validate apps].each { |anchor| assert_select "##{anchor}" }
  end

  test "the guide explains how to issue signing certificates on the ID card" do
    get how_to_sign_index_path

    assert_select "section#eid h2", text: I18n.t("how_to_sign.index.eid.title")
    assert_select "section#eid ol li", count: 5
    assert_select "section#eid", text: /Disig Web Signer/
    assert_select "section#eid a[href=?][target=_blank][rel=noopener] .sr-only", "https://navody.digital/zivotne-situacie/aktivacia-eid/krok/certifikaty", text: I18n.t("how_to_sign.index.opens_in_new_tab")
    assert_select "#sign a[href='#eid']", text: I18n.t("how_to_sign.index.guide.sign.eid_hint_link")
  end

  test "the guide embeds the video with a link to its text version" do
    get how_to_sign_index_path

    assert_select "figure video[controls][aria-label=?]", I18n.t("how_to_sign.index.video.title") do
      assert_select "source[src=?][type='video/mp4']", "https://static-ssd.s3.eu-central-1.amazonaws.com/agp.mp4"
    end
    assert_select "figcaption a[href='#guide']"
  end

  test "the video has Slovak captions and English subtitles turned on in English" do
    get how_to_sign_index_path

    assert_select "video track[kind=captions][srclang=sk]:not([default])"
    assert_select "video track[kind=subtitles][srclang=en]:not([default])"

    get how_to_sign_index_path(locale: :en)
    assert_select "video track[kind=subtitles][srclang=en][default]"

    assert_select "video[crossorigin=anonymous] track[src=?]", "https://static-ssd.s3.eu-central-1.amazonaws.com/agp.sk.vtt"
  end
end
