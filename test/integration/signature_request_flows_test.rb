require "test_helper"
require_relative "../support/signing_flow_helper"
require_relative "../support/plan_limits_helper"

# End-to-end signature requests started from the web: an organization uploads a
# document, requests signatures and recipients sign it through the real endpoints.
class SignatureRequestFlowsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionMailer::TestHelper
  include Turbo::Broadcastable::TestHelper
  include SigningFlowHelper
  include PlanLimitsHelper

  setup do
    @organization = Tenant.create!(name: "Firma ABC", plan: :pro)
    @owner = confirmed_user("owner@firma-abc.sk", tenant: @organization, role: :owner)
  end

  test "external recipient without an account signs a single document from the invitation email" do
    bundle = request_signature_from_web(as: @owner, filename: "zmluva.pdf")
    recipient = add_recipient(bundle, "external@example.com")
    sign_out @owner

    mail = mails_to("external@example.com").sole
    get link_in(mail, %r{/bundles/#{bundle.uuid}/sign})
    assert_response :success
    assert_includes response.body, "Firma ABC"
    assert_select "a[href*='#{signature_apps_contract_path(bundle.contracts.sole)}']"

    parameters = sign_with_autogram(bundle.contracts.sole, recipient: recipient)

    assert_equal [ "zmluva.pdf" ], parameters["documents"].map { |document| document["filename"] }
    assert_not parameters["multiple_documents"]
    assert bundle.reload.completed?
    assert recipient.reload.signed?
    assert_equal 1, mails_to(@owner.email).count { |m| m.subject == I18n.t("notification_mailer.bundle_completed.subject") }
  end

  test "the recipient picks Podpis na papieri on the bundle signing page" do
    with_allowed_methods(%w[qes standalone_qes ades scan]) do
      bundle = request_signature_from_web(as: @owner, filename: "papier.pdf", allowed_methods: [ "qes", "scan" ])
      contract = bundle.contracts.sole
      recipient = add_recipient(bundle, "paper@example.com")
      sign_out @owner

      get sign_bundle_path(bundle, recipient: recipient.uuid)
      assert_response :success
      assert_select "input[value=paper]"
      assert_includes response.body, "Podpis na papieri"
      assert_select "a[href=?]", "/contracts/#{contract.uuid}/paper_signature?recipient=#{recipient.uuid}"
      assert_equal "/contracts/#{contract.uuid}/paper_signature?recipient=#{recipient.uuid}", contract_paper_signature_path(contract, recipient: recipient.uuid)

      get sign_bundle_path(bundle, recipient: recipient.uuid, iframe: "no_preview")
      assert_select "input[value=paper]", count: 0
    end
  end

  test "paper signing is not offered when the author did not allow scans" do
    bundle = request_signature_from_web(as: @owner, filename: "bez-papiera.pdf")
    recipient = add_recipient(bundle, "nopaper@example.com")
    sign_out @owner

    get sign_bundle_path(bundle, recipient: recipient.uuid)
    assert_response :success
    assert_select "input[value=paper]", count: 0

    get contract_paper_signature_path(bundle.contracts.sole, recipient: recipient.uuid)
    assert_redirected_to sign_bundle_path(bundle, recipient: recipient.uuid)
    assert_equal 0, PaperSignature.count
  end

  test "recipient uploads photos of the signed pages and submits them for review" do
    with_paper_signing_request do |bundle, contract, recipient|
      get contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert_response :success
      assert_select "h1", "Podpis na papieri"
      assert_includes response.body, "Podpis potom skontroluje odosielateľ, Firma ABC."
      assert_select "a[href=?]", sign_bundle_path(bundle, recipient: recipient.uuid), text: "Späť na výber spôsobu podpisu"
      assert_select "a[href=?]", download_document_path(contract.documents.sole), text: "Stiahnuť na tlač"
      assert_select "input[type=file][name=?][multiple]", "files[]"
      assert_select "button[disabled]", text: "Odoslať na kontrolu"
      assert_select "figure", count: 0

      post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ jpeg_upload ] }
      assert_redirected_to contract_paper_signature_path(contract, recipient: recipient.uuid)
      follow_redirect!
      assert_select "figure figcaption", "Strana 1"
      assert_select "img[src*=?]", "/paper_signature/pages/"
      assert_includes response.body, "Dokument má 2 strany, nahrali ste 1"
      assert_select "button:not([disabled])", text: "Odoslať na kontrolu"

      page = PaperSignature.sole.pages.sole
      get contract_paper_signature_page_path(contract, page, recipient: recipient.uuid)
      assert_response :success
      assert_equal "image/jpeg", response.media_type
      assert response.headers["Content-Disposition"].start_with?("inline")
      assert_equal file_fixture("paper-page.jpg").binread, response.body.b

      post submit_contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert_redirected_to contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert PaperSignature.sole.submitted?
      follow_redirect!
      assert_includes response.body, "Sken sme odoslali na kontrolu"
      assert_includes response.body, "Keď podpis schváli alebo vráti, pošleme vám e-mail na paper@example.com."
      assert_select "figure figcaption", "Strana 1"

      get sign_bundle_path(bundle, recipient: recipient.uuid)
      assert_includes response.body, "Sken sme odoslali na kontrolu"
      assert_select "input[value=paper]", count: 0

      get sign_contract_path(contract, recipient: recipient.uuid)
      assert_response :success
      assert_includes response.body, "Sken sme odoslali na kontrolu"
      assert_select "input[value=paper]", count: 0
    end
  end

  test "an unsupported file is refused and the draft stays" do
    with_paper_signing_request do |_bundle, contract, recipient|
      post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ docx_upload ] }
      follow_redirect!
      assert_includes response.body, I18n.t("paper_signatures.errors.unsupported_file")
      assert PaperSignature.sole.draft?
      assert_empty PaperSignature.sole.pages

      post submit_contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert_redirected_to contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert_equal I18n.t("paper_signatures.alerts.no_pages"), flash[:alert]
      assert PaperSignature.sole.draft?, "a draft without pages is not submitted"

      post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ jpeg_upload ] }
      with_plan_limits("MAX_DOCUMENT_SIZE_MB" => "0") do
        post submit_contract_paper_signature_path(contract, recipient: recipient.uuid)
      end
      assert_redirected_to contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert_equal I18n.t("paper_signatures.errors.too_large"), flash[:alert]
      assert PaperSignature.sole.draft?
    end
  end

  test "a second visit reuses the draft" do
    with_paper_signing_request do |_bundle, contract, recipient|
      get contract_paper_signature_path(contract, recipient: recipient.uuid)
      post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ jpeg_upload ] }

      get contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert_response :success
      assert_select "figure", count: 1
      assert PaperSignature.sole.draft?
    end
  end

  test "recipient reorders and removes pages without JavaScript" do
    with_paper_signing_request do |_bundle, contract, recipient|
      post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ jpeg_upload, png_upload ] }
      paper = PaperSignature.sole
      jpeg_page, png_page = paper.pages.to_a
      follow_redirect!
      assert_select "figure", count: 2
      assert_not_includes response.body, "Dokument má 2 strany", "the same number of pages needs no warning"
      assert_select "form[action=?] input[name=position][value='1']", contract_paper_signature_page_path(contract, png_page, recipient: recipient.uuid)
      assert_select "form[action=?] input[name=_method][value=delete]", contract_paper_signature_page_path(contract, jpeg_page, recipient: recipient.uuid)

      patch contract_paper_signature_page_path(contract, png_page, recipient: recipient.uuid), params: { position: 1 }
      assert_redirected_to contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert_equal [ png_page, jpeg_page ], paper.pages.reload.to_a

      delete contract_paper_signature_page_path(contract, jpeg_page, recipient: recipient.uuid)
      assert_redirected_to contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert_equal [ png_page ], paper.pages.reload.to_a
    end
  end

  test "discarding the scan brings back the method choice" do
    with_paper_signing_request do |bundle, contract, recipient|
      post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ jpeg_upload ] }

      get sign_bundle_path(bundle, recipient: recipient.uuid)
      assert_select "input[value=paper]", count: 0
      assert_select "a[href=?]", contract_paper_signature_path(contract, recipient: recipient.uuid), text: "Pokračovať"

      post submit_contract_paper_signature_path(contract, recipient: recipient.uuid)
      get sign_bundle_path(bundle, recipient: recipient.uuid)
      assert_select "form[action=?] button", contract_paper_signature_path(contract, recipient: recipient.uuid), text: "Zahodiť sken a podpísať inak"

      delete contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert_redirected_to sign_bundle_path(bundle, recipient: recipient.uuid)
      assert PaperSignature.sole.canceled?
      follow_redirect!
      assert_select "input[value=paper]"
    end
  end

  test "uploading another scan replaces the one awaiting review" do
    with_paper_signing_request do |_bundle, contract, recipient|
      post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ jpeg_upload ] }
      post submit_contract_paper_signature_path(contract, recipient: recipient.uuid)
      follow_redirect!
      assert_select "form[action=?] button", contract_paper_signature_path(contract, recipient: recipient.uuid, restart: true), text: "Nahrať iný sken"

      delete contract_paper_signature_path(contract, recipient: recipient.uuid, restart: true)
      assert_redirected_to contract_paper_signature_path(contract, recipient: recipient.uuid)
      follow_redirect!
      assert_select "button[disabled]", text: "Odoslať na kontrolu"
      assert_equal %w[canceled draft], PaperSignature.order(:id).map(&:status)
    end
  end

  test "electronic signing is refused while a scan awaits review" do
    with_paper_signing_request do |bundle, contract, recipient|
      post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ jpeg_upload ] }
      get autogram_contract_sessions_path(contract, recipient: recipient.uuid)
      assert_response :success, "a draft does not stop electronic signing"

      post submit_contract_paper_signature_path(contract, recipient: recipient.uuid)
      [
        signature_apps_contract_path(contract, recipient: recipient.uuid),
        autogram_contract_sessions_path(contract, recipient: recipient.uuid),
        ades_contract_sessions_path(contract, recipient: recipient.uuid)
      ].each do |path|
        get path
        assert_redirected_to sign_bundle_path(bundle, recipient: recipient.uuid), "#{path} lets the recipient sign while the scan awaits review"
        assert_equal I18n.t("paper_signatures.notices.awaiting_review"), flash[:notice]
      end
      assert_equal 1, recipient.sessions.count
    end
  end

  test "an embedded signing page shows the scan awaiting review instead of forwarding to the signing apps" do
    with_paper_signing_request do |bundle, contract, recipient|
      post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ jpeg_upload ] }
      get sign_bundle_path(bundle, recipient: recipient.uuid, iframe: "no_preview")
      assert_response :redirect
      assert_includes response.location, signature_apps_contract_path(contract), "a draft lets the embedded page forward to the signing apps"

      post submit_contract_paper_signature_path(contract, recipient: recipient.uuid)
      [
        sign_bundle_path(bundle, recipient: recipient.uuid, iframe: "no_preview"),
        sign_bundle_path(bundle, recipient: recipient.uuid, iframe: "no_onboarding"),
        sign_contract_path(contract, recipient: recipient.uuid, iframe: "no_onboarding")
      ].each do |path|
        get path
        assert_response :success, "#{path} forwards the recipient although the scan awaits review"
        assert_includes response.body, I18n.t("paper_signatures.submitted.title")
        assert_select "input[value=paper]", count: 0
      end
    end
  end

  test "a signature made in a signing app opened before the scan was submitted withdraws the scan" do
    with_paper_signing_request do |bundle, contract, recipient|
      post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ jpeg_upload ] }
      in_progress = open_autogram_session(contract, recipient: recipient)
      post submit_contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert PaperSignature.sole.submitted?

      upload_signed_file(contract, in_progress[:upload])
      assert_response :success

      assert recipient.reload.signed?
      assert bundle.reload.completed?
      assert PaperSignature.sole.canceled?, "the scan of a signature made another way is no longer reviewed"
    end
  end

  test "another recipient cannot see or change the scan" do
    with_allowed_methods(PAPER_ALLOWED_METHODS) do
      other_bundle = request_signature_from_web(as: @owner, filename: "iny.pdf", allowed_methods: [ "qes", "scan" ], content: pdf_content(pages: 2))
      stranger = add_recipient(other_bundle, "stranger@example.com")
      bundle = request_signature_from_web(as: @owner, filename: "papier.pdf", allowed_methods: [ "qes", "scan" ], content: pdf_content(pages: 2))
      recipient = add_recipient(bundle, "paper@example.com")
      colleague = add_recipient(bundle, "colleague@example.com")
      sign_out @owner
      contract = bundle.contracts.sole

      post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ jpeg_upload ] }
      page = PaperSignature.sole.pages.sole

      get contract_paper_signature_path(contract, recipient: stranger.uuid)
      assert_response :not_found
      post contract_paper_signature_pages_path(contract, recipient: stranger.uuid), params: { files: [ jpeg_upload ] }
      assert_response :not_found
      get contract_paper_signature_page_path(contract, page, recipient: stranger.uuid)
      assert_response :not_found
      get contract_paper_signature_page_path(contract, page)
      assert_response :not_found

      get contract_paper_signature_page_path(contract, page, recipient: colleague.uuid)
      assert_response :not_found
      delete contract_paper_signature_page_path(contract, page, recipient: colleague.uuid)
      assert_response :not_found
      post submit_contract_paper_signature_path(contract, recipient: colleague.uuid)
      delete contract_paper_signature_path(contract, recipient: colleague.uuid)

      colleague.withdraw!
      get contract_paper_signature_path(contract, recipient: colleague.uuid)
      assert_response :not_found

      paper = PaperSignature.find_by!(signer_contract: recipient.signer_contracts.sole)
      assert paper.draft?
      assert_equal [ page ], paper.pages.to_a
      assert_equal 1, PaperSignaturePage.count
    end
  end

  test "a released recipient cannot sign on paper any more" do
    with_allowed_methods(PAPER_ALLOWED_METHODS) do
      bundle = request_signature_from_web(as: @owner, filename: "jeden-staci.pdf", allowed_methods: [ "qes", "scan" ], content: pdf_content(pages: 2))
      patch bundle_path(bundle), params: { bundle: { signing_rule: "any" } }
      first = add_recipient(bundle, "first@example.com")
      second = add_recipient(bundle, "second@example.com")
      sign_out @owner
      contract = bundle.contracts.sole

      sign_with_autogram(contract, recipient: first)
      assert second.reload.superseded?

      get contract_paper_signature_path(contract, recipient: second.uuid)
      assert_redirected_to sign_bundle_path(bundle, recipient: second.uuid)
      assert_equal I18n.t("bundles.sign.signature_no_longer_required"), flash[:notice]
      post contract_paper_signature_pages_path(contract, recipient: second.uuid), params: { files: [ jpeg_upload ] }
      assert_redirected_to sign_bundle_path(bundle, recipient: second.uuid)
      assert_equal 0, PaperSignaturePage.count
    end
  end

  test "a returned scan shows its reason on the signing pages" do
    @owner.update!(name: "Eva Kontrolná")
    with_paper_signing_request do |bundle, contract, recipient|
      post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ jpeg_upload ] }
      post submit_contract_paper_signature_path(contract, recipient: recipient.uuid)
      PaperSignature.sole.return!(@owner, "Chýba podpis na druhej strane.")

      get sign_bundle_path(bundle, recipient: recipient.uuid)
      assert_includes response.body, "Odosielateľ vrátil váš sken"
      assert_includes response.body, "Chýba podpis na druhej strane."
      assert_includes response.body, "Vrátil(a) Eva Kontrolná"
      assert_select "input[value=paper]"

      get contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert_response :success
      assert_includes response.body, "Odosielateľ vrátil váš sken"
      assert_includes response.body, "Chýba podpis na druhej strane."
      assert_select "figure", count: 0
      assert_equal %w[returned draft], PaperSignature.order(:id).map(&:status)

      get sign_bundle_path(bundle, recipient: recipient.uuid)
      assert_includes response.body, "Odosielateľ vrátil váš sken", "an empty draft leaves the returned scan in view"
      assert_select "input[value=paper]"
    end
  end

  test "the signing page shows a QR code with the phone link" do
    with_paper_signing_request do |_bundle, contract, recipient|
      phone_url = URI(phone_link_for(contract, recipient))

      assert_select "#paper_signature_phone" do
        assert_select "h3", text: "Odfoťte strany mobilom"
        assert_select "[role=img][aria-label=?][data-phone-url=?]", I18n.t("paper_signatures.phone.qr_label"), phone_url.to_s
        qr_path = Nokogiri::HTML5.fragment(ApplicationController.helpers.qr_code_svg(phone_url.to_s, level: :m)).at_css("svg path")["d"]
        assert_select "[data-phone-url] svg path[d=?]", qr_path
      end
      assert_equal [ "www.example.com", contract_paper_signature_path(contract) ], [ phone_url.host, phone_url.path ]
      assert_equal PaperSignature.sole, PaperSignatureAccessToken.verify(phone_token(phone_url))
      assert_not_includes phone_url.to_s, recipient.uuid
    end
  end

  test "the phone link adds pages to the same draft without signing in" do
    with_paper_signing_request do |_bundle, contract, recipient|
      phone_url = phone_link_for(contract, recipient)
      token = phone_token(phone_url)
      draft = PaperSignature.sole
      assert_select "turbo-cable-stream-source[signed-stream-name=?]", Turbo::StreamsChannel.signed_stream_name(draft)

      get phone_url
      assert_response :success
      assert_select "h1", text: "Odfoťte podpísané strany"
      assert_select "p", text: /papier\.pdf\s*·\s*2 strany/
      assert_select "label[for=paper_signature_files]", text: /Odfotiť ďalšiu stranu/
      assert_select "input#paper_signature_files[type=file][name='files[]'][accept='image/*'][capture=environment]"
      assert_select "label", text: /Vybrať z galérie/ do |labels|
        assert_select labels.first, "input[type=file][name='files[]'][multiple]:not([capture])"
      end
      assert_select "form[action=?] button[disabled]", submit_contract_paper_signature_path(contract, token: token), text: "Odoslať na kontrolu"
      assert_select "#paper_signature_phone", count: 0
      assert_select "a", text: "Stiahnuť na tlač", count: 0
      assert_select "a", text: "Späť na výber spôsobu podpisu", count: 0
      assert_select "button", text: "Zahodiť sken a podpísať inak", count: 0
      assert_select "turbo-cable-stream-source[signed-stream-name=?]", Turbo::StreamsChannel.signed_stream_name(draft)
      assert_not_includes response.body, recipient.uuid

      assert_turbo_stream_broadcasts draft, count: 1 do
        post contract_paper_signature_pages_path(contract, token: token), params: { files: [ jpeg_upload ] }
      end
      assert_redirected_to contract_paper_signature_path(contract, token: token)
      assert_equal 1, draft.reload.pages.count
      jpeg_page = draft.pages.sole

      follow_redirect!
      assert_select "figure figcaption", text: "Strana 1"
      assert_select "img[src=?]", contract_paper_signature_page_path(contract, jpeg_page, token: token)
      assert_select "form[action=?] button:not([disabled])", submit_contract_paper_signature_path(contract, token: token), text: "Odoslať na kontrolu (1 strana)"
      assert_includes response.body, "Dokument má 2 strany, nahrali ste 1"
      assert_not_includes response.body, recipient.uuid

      get contract_paper_signature_page_path(contract, jpeg_page, token: token)
      assert_response :success
      assert_equal "image/jpeg", response.media_type

      post contract_paper_signature_pages_path(contract, token: token), params: { files: [ png_upload ] }
      png_page = draft.pages.last
      follow_redirect!
      assert_select "form[action=?] button", submit_contract_paper_signature_path(contract, token: token), text: "Odoslať na kontrolu (2 strany)"
      patch contract_paper_signature_page_path(contract, png_page, token: token), params: { position: 1 }
      assert_redirected_to contract_paper_signature_path(contract, token: token)
      assert_equal [ png_page, jpeg_page ], draft.pages.reload.to_a
      delete contract_paper_signature_page_path(contract, png_page, token: token)
      assert_redirected_to contract_paper_signature_path(contract, token: token)
      assert_equal [ jpeg_page ], draft.pages.reload.to_a

      get contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert_select "figure figcaption", text: "Strana 1"

      post submit_contract_paper_signature_path(contract, token: token)
      assert_redirected_to contract_paper_signature_path(contract, token: token)
      assert draft.reload.submitted?
      follow_redirect!
      assert_response :gone
      assert_includes response.body, "Sken sme odoslali na kontrolu"
      assert_not_includes response.body, "Odkaz na fotenie už neplatí"
      assert_not_includes response.body, recipient.email
    end
  end

  test "an expired phone link changes nothing" do
    with_paper_signing_request do |_bundle, contract, recipient|
      get contract_paper_signature_path(contract, recipient: recipient.uuid)
      draft = PaperSignature.sole
      token = PaperSignatureAccessToken.generate(draft, expires_at: 1.minute.ago)

      post contract_paper_signature_pages_path(contract, token: token), params: { files: [ jpeg_upload ] }
      assert_response :gone
      assert_equal 0, draft.reload.pages.count

      get contract_paper_signature_path(contract, token: token)
      assert_response :gone
      assert_select "h1", text: "Odkaz na fotenie už neplatí"
      assert_includes response.body, "Otvorte stránku podpisu na počítači a naskenujte nový kód."

      fresh_token = PaperSignatureAccessToken.generate(draft)
      travel 61.minutes do
        post contract_paper_signature_pages_path(contract, token: fresh_token), params: { files: [ jpeg_upload ] }
        assert_response :gone
      end
      get contract_paper_signature_path(contract, token: "#{fresh_token}x")
      assert_response :gone
      assert_equal 0, draft.reload.pages.count
    end
  end

  test "a phone link of one contract does not open another" do
    with_allowed_methods(PAPER_ALLOWED_METHODS) do
      other_bundle = request_signature_from_web(as: @owner, filename: "iny.pdf", allowed_methods: [ "qes", "scan" ], content: pdf_content(pages: 2))
      stranger = add_recipient(other_bundle, "stranger@example.com")
      bundle = request_signature_from_web(as: @owner, filename: "papier.pdf", allowed_methods: [ "qes", "scan" ], content: pdf_content(pages: 2))
      recipient = add_recipient(bundle, "paper@example.com")
      colleague = add_recipient(bundle, "colleague@example.com")
      sign_out @owner
      contract = bundle.contracts.sole
      other_contract = other_bundle.contracts.sole

      token = phone_token(phone_link_for(contract, recipient))
      post contract_paper_signature_pages_path(contract, token: token), params: { files: [ jpeg_upload ] }
      page = PaperSignature.sole.pages.sole
      post contract_paper_signature_pages_path(other_contract, recipient: stranger.uuid), params: { files: [ jpeg_upload ] }
      other_page = PaperSignaturePage.where.not(id: page).sole
      post contract_paper_signature_pages_path(contract, recipient: colleague.uuid), params: { files: [ jpeg_upload ] }
      colleague_page = PaperSignaturePage.where.not(id: [ page, other_page ]).sole

      get contract_paper_signature_path(other_contract, token: token)
      assert_response :not_found
      post contract_paper_signature_pages_path(other_contract, token: token), params: { files: [ jpeg_upload ] }
      assert_response :not_found
      get contract_paper_signature_page_path(other_contract, other_page, token: token)
      assert_response :not_found
      post submit_contract_paper_signature_path(other_contract, token: token)
      assert_response :not_found

      get contract_paper_signature_page_path(contract, colleague_page, token: token)
      assert_response :not_found
      delete contract_paper_signature_page_path(contract, colleague_page, token: token)
      assert_response :not_found

      assert_equal 3, PaperSignaturePage.count
      assert PaperSignature.all.all?(&:draft?)
    end
  end

  test "the phone link stops working after the scan is submitted" do
    with_paper_signing_request do |_bundle, contract, recipient|
      token = phone_token(phone_link_for(contract, recipient))
      post contract_paper_signature_pages_path(contract, token: token), params: { files: [ jpeg_upload ] }
      page = PaperSignature.sole.pages.sole
      post submit_contract_paper_signature_path(contract, recipient: recipient.uuid)
      assert PaperSignature.sole.submitted?

      get contract_paper_signature_path(contract, token: token)
      assert_response :gone
      assert_includes response.body, "Sken sme odoslali na kontrolu"
      post contract_paper_signature_pages_path(contract, token: token), params: { files: [ jpeg_upload ] }
      assert_response :gone
      get contract_paper_signature_page_path(contract, page, token: token)
      assert_response :gone
      post submit_contract_paper_signature_path(contract, token: token)
      assert_response :gone
      assert_equal [ page ], PaperSignature.sole.pages.to_a

      delete contract_paper_signature_path(contract, recipient: recipient.uuid, restart: true)
      follow_redirect!
      new_draft = PaperSignature.draft.sole

      get contract_paper_signature_path(contract, token: token)
      assert_response :gone
      assert_select "h1", text: "Odkaz na fotenie už neplatí"
      post contract_paper_signature_pages_path(contract, token: token), params: { files: [ jpeg_upload ] }
      assert_response :gone
      assert_equal 0, new_draft.pages.count
    end
  end

  test "a phone link cannot discard the scan" do
    with_paper_signing_request do |_bundle, contract, recipient|
      token = phone_token(phone_link_for(contract, recipient))
      post contract_paper_signature_pages_path(contract, token: token), params: { files: [ jpeg_upload ] }

      delete contract_paper_signature_path(contract, token: token)
      assert_response :forbidden
      delete contract_paper_signature_path(contract, token: token, restart: true)
      assert_response :forbidden

      draft = PaperSignature.sole
      assert draft.draft?
      assert_equal 1, draft.pages.count
    end
  end

  test "a phone link stops working after the recipient is withdrawn" do
    with_paper_signing_request do |bundle, contract, recipient|
      token = phone_token(phone_link_for(contract, recipient))
      post contract_paper_signature_pages_path(contract, token: token), params: { files: [ jpeg_upload ] }
      assert_equal 1, PaperSignaturePage.count

      sign_in_with_tenant @owner, @organization
      delete bundle_recipient_path(bundle, recipient), as: :turbo_stream
      assert recipient.reload.withdrawn?
      sign_out @owner

      get contract_paper_signature_path(contract, token: token)
      assert_response :gone
      post contract_paper_signature_pages_path(contract, token: token), params: { files: [ jpeg_upload ] }
      assert_response :gone
      assert_equal 0, PaperSignaturePage.count
    end
  end

  test "author names the bundle and writes a message before the invitation goes out" do
    bundle = request_signature_from_web(as: @owner, filename: "zmluva-o-dielo.pdf")

    follow_redirect!
    assert_select "h1", text: I18n.t("bundles.edit.preparing_title")
    assert_select "input[name='bundle[name]'][value=?]", "zmluva-o-dielo"
    assert_select "input[name='bundle[signing_rule]']", count: 0

    patch bundle_path(bundle), params: { bundle: { name: "Zmluva o dielo – kancelária", note: "Prosím o podpis do piatka." } }
    assert_redirected_to bundle_path(bundle)
    recipient = add_recipient(bundle, "external@example.com")

    mail = mails_to("external@example.com").sole
    assert_equal I18n.t("notification_mailer.signature_requested.subject"), mail.subject
    assert_includes mail.html_part.body.decoded, "Zmluva o dielo – kancelária"
    assert_includes mail.html_part.body.decoded, "Prosím o podpis do piatka."

    get edit_bundle_path(bundle)
    assert_select "h1", text: I18n.t("bundles.edit.title")
    assert_select "h2", text: I18n.t("bundles.edit.invited_warning_title", count: 1)
    assert_select "p", text: recipient.display_name
  end

  test "colleague from the same organization signs while signed in and sees the request on both sides" do
    colleague = confirmed_user("colleague@firma-abc.sk", tenant: @organization)
    bundle = request_signature_from_web(as: @owner, filename: "interna.pdf")
    recipient = add_recipient(bundle, colleague.email)
    assert_equal colleague, recipient.user
    sign_out @owner

    sign_in_with_tenant colleague, @organization
    get bundles_path
    assert_select "a[href=?]", bundle_path(bundle), text: bundle.display_name
    get received_bundles_path
    assert_select "a[href=?]", sign_bundle_path(bundle, recipient: recipient.uuid), text: bundle.display_name

    get sign_bundle_path(bundle)
    assert_response :success
    sign_with_autogram(bundle.contracts.sole)

    assert recipient.reload.signed?
    assert bundle.reload.completed?
    assert_equal [ recipient ], bundle.recipients.to_a, "a colleague signs as the recipient, not as an author proxy"
  end

  test "recipient from another organization signs in their own organization without access to the sender's data" do
    outsider = confirmed_user("outsider@inafirma.sk")
    bundle = request_signature_from_web(as: @owner, filename: "dodavatel.pdf")
    recipient = add_recipient(bundle, outsider.email)
    sign_out @owner

    sign_in outsider
    get received_bundles_path
    assert_select "a[href=?]", sign_bundle_path(bundle, recipient: recipient.uuid), text: bundle.display_name
    get bundles_path
    assert_not_includes response.body, bundle_path(bundle)
    get bundle_path(bundle)
    assert_response :not_found

    sign_with_autogram(bundle.contracts.sole)

    assert bundle.reload.completed?
    assert_not outsider.member_of?(@organization)
  end

  test "whoever completes a bundle for a recipient gets no completion mail" do
    bundle = request_signature_from_web(as: @owner, filename: "papier.pdf")
    recipient = add_recipient(bundle, "external@example.com")
    sign_out @owner

    perform_enqueued_jobs { recipient.recipient_signer.signer_contracts.sole.complete_signature!(except: @owner) }

    assert bundle.reload.completed?
    assert_empty mails_to(@owner.email).select { |m| m.subject == I18n.t("notification_mailer.bundle_completed.subject") }
  end

  test "with several recipients the bundle waits for all of them and its author is told about each signature" do
    co_owner = confirmed_user("co-owner@firma-abc.sk", tenant: @organization, role: :owner)
    bundle = request_signature_from_web(as: @owner, filename: "spolocna.pdf")
    assert_equal @owner, bundle.author
    first = add_recipient(bundle, "first@example.com")
    second = add_recipient(bundle, "second@example.com")
    sign_out @owner
    contract = bundle.contracts.sole

    sign_with_autogram(contract, recipient: first)

    assert first.reload.signed?
    assert second.reload.pending?
    assert_not bundle.reload.completed?
    assert_equal 1, mails_to(@owner.email).count { |m| m.subject == I18n.t("notification_mailer.bundle_contract_signed.subject") }

    sign_with_autogram(contract, recipient: second)

    assert bundle.reload.completed?
    assert_equal 1, mails_to(@owner.email).count { |m| m.subject == I18n.t("notification_mailer.bundle_completed.subject") }
    assert_empty mails_to(co_owner.email), "other owners are not told about bundles they did not send"
  end

  test "a member's bundle notifies the member, not the owners" do
    member = confirmed_user("member@firma-abc.sk", tenant: @organization)
    bundle = request_signature_from_web(as: member, filename: "clenska.pdf")
    recipient = add_recipient(bundle, "partner@example.com")
    sign_out member

    sign_with_autogram(bundle.contracts.sole, recipient: recipient)

    assert bundle.reload.completed?
    assert_equal member, bundle.author
    assert_equal 1, mails_to(member.email).count { |m| m.subject == I18n.t("notification_mailer.bundle_completed.subject") }
    assert_empty mails_to(@owner.email)
  end

  test "with the any rule the first signature completes the bundle and releases the other recipients" do
    bundle = request_signature_from_web(as: @owner, filename: "jeden-staci.pdf")
    patch bundle_path(bundle), params: { bundle: { signing_rule: "any" } }
    assert_redirected_to bundle_path(bundle)
    first = add_recipient(bundle, "first@example.com")
    second = add_recipient(bundle, "second@example.com")
    sign_out @owner

    sign_with_autogram(bundle.contracts.sole, recipient: first)

    assert bundle.reload.completed?
    assert second.reload.superseded?
    assert_equal 1, mails_to(second.email).count { |m| m.subject == I18n.t("notification_mailer.signature_no_longer_required.subject") }

    get sign_bundle_path(bundle, recipient: second.uuid)
    assert_response :success
    contract = bundle.contracts.sole
    assert_select "a[href*='#{autogram_contract_sessions_path(contract)}']", count: 0
    assert_select "a[href*='#{signature_apps_contract_path(contract)}']", count: 0
  end

  test "released recipient can no longer sign, not even with a signing already in progress" do
    bundle = request_signature_from_web(as: @owner, filename: "jeden-staci.pdf")
    patch bundle_path(bundle), params: { bundle: { signing_rule: "any" } }
    first = add_recipient(bundle, "first@example.com")
    second = add_recipient(bundle, "second@example.com")
    sign_out @owner
    contract = bundle.contracts.sole

    in_progress = open_autogram_session(contract, recipient: second)
    sign_with_autogram(contract, recipient: first)
    assert second.reload.superseded?
    assert second.sessions.sole.canceled?, "the released recipient's pending signing is cancelled"

    upload_signed_file(contract, in_progress[:upload])
    assert_response :bad_request
    assert_equal I18n.t("bundles.sign.signature_no_longer_required"), response.parsed_body["error"]
    assert_equal 1, contract.reload.content_versions.count

    [
      autogram_contract_sessions_path(contract, recipient: second.uuid),
      ades_contract_sessions_path(contract, recipient: second.uuid),
      sign_contract_path(contract, recipient: second.uuid),
      signature_apps_contract_path(contract, recipient: second.uuid)
    ].each do |path|
      get path
      assert_redirected_to sign_bundle_path(bundle, recipient: second.uuid), "#{path} still lets a released recipient sign"
      assert_equal I18n.t("bundles.sign.signature_no_longer_required"), flash[:notice]
    end
    assert_equal 1, second.sessions.count
  end

  test "a recipient who declines the bundle withdraws the scan they submitted for review" do
    bundle = request_signature_from_web(as: @owner, filename: "papier.pdf")
    recipient = add_recipient(bundle, "external@example.com")
    sign_out @owner
    paper = PaperSignature.open_for!(recipient.recipient_signer.signer_contracts.sole)
    paper.add_pages!([ Rack::Test::UploadedFile.new(file_fixture("paper-page.jpg"), "image/jpeg") ])
    assert paper.submit!

    post decline_bundle_path(bundle, recipient: recipient.uuid)

    assert_redirected_to sign_bundle_path(bundle, recipient: recipient.uuid)
    assert recipient.reload.declined?
    assert paper.reload.canceled?
  end

  test "owner signs their own request too and nobody is notified about it" do
    co_owner = confirmed_user("co-owner@firma-abc.sk", tenant: @organization, role: :owner)
    bundle = request_signature_from_web(as: @owner, filename: "obojstranna.pdf")
    recipient = add_recipient(bundle, "partner@example.com")

    get sign_bundle_path(bundle)
    assert_response :success
    sign_with_autogram(bundle.contracts.sole)

    author_proxy = bundle.recipients.author_proxies.sole
    assert_equal @owner, author_proxy.user
    assert_not bundle.reload.completed?, "the author's signature does not replace the recipient's"
    assert_empty mails_to(@owner.email).select { |m| m.subject == I18n.t("notification_mailer.bundle_contract_signed.subject") }
    assert_empty mails_to(co_owner.email), "the author's own signature is not news for the other owners"
    sign_out @owner

    sign_with_autogram(bundle.contracts.sole, recipient: recipient)

    assert bundle.reload.completed?
  end

  test "member uploads and signs a standalone document and nobody is notified" do
    member = confirmed_user("member@firma-abc.sk", tenant: @organization)
    sign_in_with_tenant member, @organization
    post contracts_path, params: { document: { blob: Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 vlastny"), "application/pdf", original_filename: "vlastny.pdf") } }
    contract = Contract.order(:id).last
    assert_equal @organization, contract.tenant

    patch contract_path(contract), params: {
      next_step: "sign",
      contract: { allowed_methods: [ "qes" ], signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" } }
    }
    assert_redirected_to sign_contract_path(contract)
    sign_with_autogram(contract)

    assert contract.reload.signed_document_attached?
    assert_nil contract.bundle
    assert_equal member, contract.author
    assert_empty mails_to(@owner.email)
    assert_empty mails_to(member.email)
  end

  test "documents sent to recipients count once towards the monthly limit and sending stops at it" do
    with_plan_limits("PRO_MONTHLY_SIGNATURE_REQUESTS" => "1") do
      bundle = request_signature_from_web(as: @owner, filename: "prva.pdf")
      add_recipient(bundle, "first@example.com")
      add_recipient(bundle, "second@example.com")
      assert_equal 1, @organization.usage_of(:signature_requests), "the same document is counted once"

      second_bundle = request_signature_from_web(as: @owner, filename: "druha.pdf")
      recipient = add_recipient_without_notifying(second_bundle, "third@example.com")
      post notify_bundle_recipient_path(second_bundle, recipient), as: :turbo_stream

      assert_response :success
      assert_includes response.body, I18n.t("plan_limits.exceeded.signature_requests", used: 1, max: 1)
      assert recipient.reload.not_notified?
      assert_empty mails_to("third@example.com")
      assert_equal 1, @organization.usage_of(:signature_requests)
    end
  end

  test "a bundle shared by a link counts when a recipient signs and cannot be signed beyond the limit" do
    with_plan_limits("PRO_MONTHLY_SIGNATURE_REQUESTS" => "1") do
      bundle = request_signature_from_web(as: @owner, filename: "zdielana.pdf")
      recipient = add_recipient_without_notifying(bundle, "linked@example.com")
      over_limit = request_signature_from_web(as: @owner, filename: "nad-limit.pdf")
      over_limit_recipient = add_recipient_without_notifying(over_limit, "other@example.com")
      sign_out @owner

      sign_with_autogram(bundle.contracts.sole, recipient: recipient)

      assert bundle.reload.completed?
      assert_equal [ "recipient_signature" ], @organization.usage_records.signature_request.pluck(:source)

      contract = over_limit.contracts.sole
      get sign_bundle_path(over_limit, recipient: over_limit_recipient.uuid)
      assert_response :forbidden
      assert_includes response.body, I18n.t("bundles.sign_limit_reached.title")

      get sign_contract_path(contract, recipient: over_limit_recipient.uuid)
      assert_response :forbidden

      get autogram_contract_sessions_path(contract, recipient: over_limit_recipient.uuid)
      assert_response :unprocessable_entity
      assert_equal 0, contract.sessions.count
      assert_equal 1, @organization.usage_of(:signature_requests)
    end
  end

  test "a standalone document counts once when someone else than its author signs it" do
    colleague = confirmed_user("colleague@firma-abc.sk", tenant: @organization)
    sign_in_with_tenant @owner, @organization
    upload_pdf("samostatna.pdf")
    contract = Contract.order(:id).last
    assert_equal @organization, contract.tenant
    assert_equal @owner, contract.author
    assert_nil contract.bundle

    sign_with_autogram(contract)
    assert_equal 0, @organization.usage_of(:signature_requests), "the author signing their own document"
    sign_out @owner

    sign_in_with_tenant colleague, @organization
    sign_with_autogram(contract)
    record = @organization.usage_records.signature_request.sole
    assert_equal "standalone_signature", record.source
    assert record.signed_at
    sign_out colleague

    sign_with_autogram(contract)
    assert_equal 1, @organization.usage_of(:signature_requests), "further signatures do not count again"
  end

  test "a colleague signing a bundle of the organization counts its document" do
    colleague = confirmed_user("colleague@firma-abc.sk", tenant: @organization)
    bundle = request_signature_from_web(as: @owner, filename: "interna.pdf")
    sign_out @owner

    sign_in_with_tenant colleague, @organization
    get sign_bundle_path(bundle)
    assert_response :success
    sign_with_autogram(bundle.contracts.sole)

    assert_equal colleague, bundle.recipients.author_proxies.sole.user
    record = @organization.usage_records.signature_request.sole
    assert_equal "recipient_signature", record.source
    assert record.signed_at
  end

  test "asking the author to sign does not count the document, asking a colleague does" do
    colleague = confirmed_user("colleague@firma-abc.sk", tenant: @organization)
    bundle = request_signature_from_web(as: @owner, filename: "na-podpis.pdf")

    add_recipient(bundle, @owner.email)
    assert_equal 0, @organization.usage_of(:signature_requests)

    recipient = add_recipient(bundle, colleague.email)
    record = @organization.usage_records.signature_request.sole
    assert_equal "notification", record.source
    assert_nil record.signed_at
    sign_out @owner

    sign_with_autogram(bundle.contracts.sole, recipient: recipient)
    assert record.reload.signed_at, "remembers when the counted document was signed"
    assert_equal 1, @organization.usage_of(:signature_requests)
  end

  test "a standalone document cannot be signed from outside the organization beyond the limit" do
    with_plan_limits("PRO_MONTHLY_SIGNATURE_REQUESTS" => "0") do
      sign_in_with_tenant @owner, @organization
      upload_pdf("nad-limit.pdf")
      contract = Contract.order(:id).last
      sign_out @owner

      get sign_contract_path(contract)
      assert_response :forbidden
      assert_includes response.body, I18n.t("bundles.sign_limit_reached.title")

      get autogram_contract_sessions_path(contract)
      assert_response :unprocessable_entity
      assert_equal 0, contract.sessions.count

      sign_in_with_tenant @owner, @organization
      sign_with_autogram(contract)
      assert_equal 0, @organization.usage_of(:signature_requests)
    end
  end

  test "the organization signing its own bundle does not count it as sent" do
    with_plan_limits("PRO_MONTHLY_SIGNATURE_REQUESTS" => "0") do
      bundle = request_signature_from_web(as: @owner, filename: "vlastna.pdf")

      get sign_bundle_path(bundle)
      assert_response :success
      sign_with_autogram(bundle.contracts.sole)

      assert bundle.recipients.author_proxies.sole.signed?
      assert_equal 0, @organization.usage_of(:signature_requests)
    end
  end

  test "uploading beyond the stored documents limit explains why" do
    with_plan_limits("PRO_MAX_STORED_DOCUMENTS" => "1") do
      sign_in_with_tenant @owner, @organization
      upload_pdf("prvy.pdf")
      assert_redirected_to contract_path(Contract.order(:id).last)

      assert_no_difference -> { Contract.count } do
        upload_pdf("druhy.pdf")
      end
      assert_response :unprocessable_entity
      assert_includes response.body, I18n.t("activerecord.errors.models.contract.attributes.base.stored_documents_limit", max: 1)
    end
  end

  test "an anonymous document stays anonymous when the organization has no room for it after sign-in" do
    with_plan_limits("PRO_MAX_STORED_DOCUMENTS" => "0") do
      upload_pdf("anonymny.pdf", agree_to_policies: true)
      contract = Contract.order(:id).last
      assert contract.anonymous?

      post authenticate_for_actions_contract_path(contract)
      sign_in_with_tenant @owner, @organization
      get contract_path(contract)

      assert_response :success
      assert contract.reload.anonymous?
      assert_includes response.body, I18n.t("activerecord.errors.models.contract.attributes.base.stored_documents_limit", max: 0)
    end
  end

  test "the sidebar links the current tenant to its settings and names a Basic tenant generically" do
    organization_link = "a[href='#{edit_user_registration_path(anchor: "organization")}']"

    sign_in_with_tenant(@owner, @organization)
    get dashboard_path
    assert_select organization_link, text: /Firma ABC\s*#{I18n.t("tenants.plans.pro")}/

    sign_out @owner
    sign_in_with_tenant(@owner, @owner.tenants.basic.sole)
    get dashboard_path
    assert_select organization_link, text: I18n.t("header.current_tenant.personal")
  end

  test "the organization sees its plan usage on the dashboard and in its settings" do
    with_plan_limits("PRO_MONTHLY_SIGNATURE_REQUESTS" => "10", "PRO_MAX_STORED_DOCUMENTS" => nil, "PRO_STORAGE_GB" => nil, "PRO_MONTHLY_TIMESTAMPS" => nil) do
      bundle = request_signature_from_web(as: @owner, filename: "pocitana.pdf")
      add_recipient(bundle, "partner@example.com")
      other = Tenant.create!(name: "Iná firma", plan: :pro)
      other.usage_records.create!(kind: :signature_request, source: :notification)

      get dashboard_path
      assert_response :success
      assert_select "section[aria-labelledby=dashboard-usage-title]", text: /#{I18n.t("tenants.usage.title")}/ do
        assert_select "li", count: 2
        assert_select "li", text: /#{I18n.t("tenants.usage.limits.signature_requests")}\s*1 \/ 10/
        assert_select "li", text: /#{I18n.t("tenants.usage.limits.timestamps")}\s*0\z/
      end

      get edit_user_registration_path
      assert_response :success
      assert_includes response.body, I18n.t("tenants.usage.limits.stored_documents")
      assert_includes response.body, I18n.t("tenants.usage.unlimited_value", used: 1)
      assert_select "[role=progressbar][aria-valuenow='1'][aria-valuemax='10']"
    end
  end

  test "the dashboard lists bundles awaiting my signature until I sign them" do
    outsider = confirmed_user("partner@inafirma.sk")
    awaiting_bundle = request_signature_from_web(as: @owner, filename: "na-podpis.pdf")
    recipient = add_recipient(awaiting_bundle, outsider.email)
    foreign_bundle = request_signature_from_web(as: @owner, filename: "pre-ineho.pdf")
    add_recipient(foreign_bundle, "iny@example.com")
    sign_out @owner

    sign_in outsider
    get dashboard_path
    assert_response :success
    assert outsider.tenants.sole.basic?
    assert_select "#organization-overview-title", count: 0
    assert_select "section[aria-labelledby=awaiting-signature-title]" do
      assert_select "#awaiting-signature-title", text: I18n.t("dashboard.index.awaiting.title_with_count", count: 1)
      assert_select "li", count: 1
      assert_select "a[href=?]", sign_bundle_path(awaiting_bundle, recipient: recipient.uuid),
                    text: "#{I18n.t("actions.view")}: #{awaiting_bundle.display_name}"
      assert_select "a[href*=?]", foreign_bundle.uuid, count: 0
    end

    sign_with_autogram(awaiting_bundle.contracts.sole, recipient: recipient)
    assert recipient.reload.signed?

    get dashboard_path
    assert_select "section[aria-labelledby=awaiting-signature-title]" do
      assert_select "#awaiting-signature-title", text: I18n.t("dashboard.index.awaiting.title")
      assert_select "li", count: 0
      assert_select "span", text: I18n.t("dashboard.index.awaiting.empty")
    end
  end

  test "a PRO dashboard shows my signatures above the organization overview" do
    colleague = confirmed_user("colleague@firma-abc.sk", tenant: @organization)
    organization_bundle = request_signature_from_web(as: @owner, filename: "organizacna.pdf")
    add_recipient(organization_bundle, "partner@example.com")
    awaiting_me_bundle = request_signature_from_web(as: @owner, filename: "osobna.pdf")
    recipient = add_recipient(awaiting_me_bundle, colleague.email)
    sign_out @owner

    sign_in_with_tenant colleague, @organization
    get dashboard_path
    assert_response :success

    assert_select "#organization-overview-title", text: I18n.t("dashboard.index.organization.title")
    assert_select "section[aria-labelledby=organization-overview-title] p strong", text: "Firma ABC"

    assert_select "section[aria-labelledby=awaiting-signature-title]" do
      assert_select "#awaiting-signature-title", text: I18n.t("dashboard.index.awaiting.title_with_count", count: 1)
      assert_select "a[href=?]", sign_bundle_path(awaiting_me_bundle, recipient: recipient.uuid)
      assert_select "a[href*=?]", organization_bundle.uuid, count: 0
    end

    awaiting_me_row = recent_bundle_row(awaiting_me_bundle)
    organization_row = recent_bundle_row(organization_bundle)
    assert_includes awaiting_me_row.text, I18n.t("bundles.bundle_list.kind_awaiting_me")
    assert_not_includes organization_row.text, I18n.t("bundles.bundle_list.kind_awaiting_me")
  end

  test "a Basic organization sees documents it signed for others only within the signed history" do
    with_plan_limits("BASIC_RETENTION_DAYS" => "60", "SIGNED_HISTORY_DAYS" => "60") do
      outsider = confirmed_user("outsider@inafirma.sk")
      old_bundle = request_signature_from_web(as: @owner, filename: "stara.pdf")
      old_recipient = add_recipient(old_bundle, outsider.email)
      awaiting_bundle = request_signature_from_web(as: @owner, filename: "cakajuca.pdf")
      awaiting_recipient = add_recipient(awaiting_bundle, outsider.email)
      sign_out @owner
      sign_with_autogram(old_bundle.contracts.sole, recipient: old_recipient)
      old_bundle.update_column(:created_at, 61.days.ago)
      awaiting_bundle.update_column(:created_at, 61.days.ago)

      sign_in outsider
      get received_bundles_path

      assert_not_includes response.body, sign_bundle_path(old_bundle, recipient: old_recipient.uuid)
      assert_includes response.body, sign_bundle_path(awaiting_bundle, recipient: awaiting_recipient.uuid)
    end
  end

  private

  PAPER_ALLOWED_METHODS = %w[qes standalone_qes ades scan].freeze

  # Sends a two-page PDF that may be signed on paper to one recipient and yields to the recipient
  # without an account (signed out).
  def with_paper_signing_request
    with_allowed_methods(PAPER_ALLOWED_METHODS) do
      bundle = request_signature_from_web(as: @owner, filename: "papier.pdf", allowed_methods: [ "qes", "scan" ], content: pdf_content(pages: 2))
      recipient = add_recipient(bundle, "paper@example.com")
      sign_out @owner

      yield bundle, bundle.contracts.sole, recipient
    end
  end

  # Opens the paper signing page on the computer and returns the phone link from its QR panel.
  def phone_link_for(contract, recipient)
    get contract_paper_signature_path(contract, recipient: recipient.uuid)
    assert_response :success
    css_select("#paper_signature_phone [data-phone-url]").sole["data-phone-url"]
  end

  def phone_token(phone_url)
    Rack::Utils.parse_query(URI(phone_url.to_s).query).fetch("token")
  end

  def pdf_content(pages:)
    Prawn::Document.new do |pdf|
      pages.times do |index|
        pdf.start_new_page if index.positive?
        pdf.text "Strana #{index + 1}"
      end
    end.render
  end

  def jpeg_upload
    Rack::Test::UploadedFile.new(file_fixture("paper-page.jpg"), "image/jpeg")
  end

  def png_upload
    Rack::Test::UploadedFile.new(file_fixture("paper-page.png"), "image/png")
  end

  def docx_upload
    Rack::Test::UploadedFile.new(StringIO.new("PK\x03\x04 word/document.xml".b), "application/vnd.openxmlformats-officedocument.wordprocessingml.document", original_filename: "zmluva.docx")
  end

  def with_allowed_methods(methods)
    original_allowed_methods = Contract::ALLOWED_METHODS
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, methods)

    yield
  ensure
    Contract.send(:remove_const, :ALLOWED_METHODS)
    Contract.const_set(:ALLOWED_METHODS, original_allowed_methods)
  end

  def upload_pdf(filename, agree_to_policies: false)
    params = { document: { blob: Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4 #{filename}"), "application/pdf", original_filename: filename) } }
    params[:contract] = { agree_to_policies: "1" } if agree_to_policies
    post contracts_path, params: params
  end

  def add_recipient_without_notifying(bundle, email)
    post bundle_recipients_path(bundle), params: { recipient: { email: email } }, as: :turbo_stream
    assert_response :success
    bundle.recipients.active.find_by!(email: email)
  end

  # Uploads a PDF, asks for signatures and returns the bundle the web creates.
  def request_signature_from_web(as:, filename:, allowed_methods: [ "qes" ], content: "%PDF-1.4 #{filename}")
    sign_in_with_tenant as, @organization
    post contracts_path, params: { document: { blob: Rack::Test::UploadedFile.new(StringIO.new(content), "application/pdf", original_filename: filename) } }
    contract = Contract.order(:id).last
    assert_redirected_to contract_path(contract)
    assert_equal @organization, contract.tenant

    patch contract_path(contract), params: {
      next_step: "request_signature",
      contract: { allowed_methods: allowed_methods, signature_parameters_attributes: { level: "BASELINE_B", format: "PAdES" } }
    }
    bundle = contract.reload.bundle
    assert_redirected_to edit_bundle_path(bundle)
    assert_equal contract.tenant, bundle.tenant
    bundle
  end

  def recent_bundle_row(bundle)
    link = css_select("section[aria-labelledby=recent-bundles-title] a[href='#{bundle_path(bundle)}']").first
    assert link, "#{bundle.display_name} is not among the recent bundles"
    link.ancestors("div.px-4").first
  end

  def add_recipient(bundle, email)
    post bundle_recipients_path(bundle), params: { recipient: { email: email } }, as: :turbo_stream
    assert_response :success
    recipient = bundle.recipients.active.find_by!(email: email)

    post notify_bundle_recipient_path(bundle, recipient), as: :turbo_stream
    assert_response :success
    assert recipient.reload.notified?
    recipient
  end
end
