# Takes the screenshots of the user guide (app/views/docs/index.html.erb) in every locale:
#
#   bin/rails test test/user_guide/screenshots.rb
#
# The file does not end in _test.rb, so the regular suite (bin/rails test, test:system) skips it.
# It fills the test database with fictional data, fakes the Autogram service and writes the images
# to public/docs/screenshots/<locale>/<name>.webp. Check the images and commit them with the guide.

# Signing methods offered in production (Contract::ALLOWED_METHODS is read when the class loads)
# and plan limits of a typical instance, so the screenshots show what users see.
ENV["ALLOWED_METHODS"] = "qes,ades"
{
  "BASIC_MAX_STORED_DOCUMENTS" => "10",
  "BASIC_MONTHLY_SIGNATURE_REQUESTS" => "10",
  "BASIC_MONTHLY_TIMESTAMPS" => "10",
  "BASIC_RETENTION_DAYS" => "60",
  "PRO_STORAGE_GB" => "50",
  "MAX_DOCUMENT_SIZE_MB" => "25"
}.each { |key, value| ENV[key] = value }
ENV.delete("FEDERATION_BASE_URL")

require "application_system_test_case"

class UserGuideScreenshots < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  OUTPUT_DIR = Rails.root.join("public/docs/screenshots")
  WINDOW_WIDTH = 1360
  VIEWPORT_HEIGHT = 1600

  driven_by :selenium, using: :headless_chrome, screen_size: [ WINDOW_WIDTH, VIEWPORT_HEIGHT ] do |options|
    options.add_argument("--hide-scrollbars")
  end

  # Answers validation requests for the signed files registered by the demo data, and shows PDFs as they are.
  class DemoAutogramService < AutogramService
    Response = Struct.new(:status, :body) do
      def success?
        status == 200
      end
    end

    def initialize
      super
      @validations = {}
    end

    def register_signed(content, validation)
      @validations[Digest::SHA256.hexdigest(content)] = validation
    end

    private

    def call_autogram_validate_api(file_content)
      validation = @validations[Digest::SHA256.hexdigest(Base64.strict_decode64(file_content))]
      validation ? Response.new(200, validation) : Response.new(422, { "code" => "DOCUMENT_NOT_SIGNED" })
    end

    def call_autogram_visualization_api(file_content, document)
      Response.new(200, { "content" => file_content, "mimeType" => "application/pdf;base64", "filename" => document.filename.to_s })
    end
  end

  DEMO = {
    sk: {
      organization: "Novák & partneri, s.r.o.",
      cooperative: "Stavebné bytové družstvo Rozvoj",
      supplier: "Tlačiareň Svit, s.r.o.",
      documents: {
        declaration: "Čestné vyhlásenie",
        power_of_attorney: "Plná moc",
        invoice: "Faktúra 2026-0142",
        leave_request: "Žiadosť o dovolenku"
      },
      bundles: {
        works: [ "Zmluva o dielo – rekonštrukcia kúpeľne", [ "Zmluva o dielo", "Príloha 1 – rozpočet" ] ],
        lease: [ "Nájomná zmluva – byt Hlavná 12", [ "Nájomná zmluva" ] ],
        termination: [ "Dohoda o ukončení spolupráce", [ "Dohoda o ukončení spolupráce" ] ],
        car: [ "Kúpna zmluva – osobný automobil", [ "Kúpna zmluva" ] ],
        minutes: [ "Zápisnica z členskej schôdze", [ "Zápisnica z členskej schôdze" ] ],
        loan: [ "Zmluva o pôžičke", [ "Zmluva o pôžičke" ] ],
        order: [ "Objednávka tlačovín", [ "Objednávka tlačovín" ] ],
        nda: [ "Dohoda o mlčanlivosti", [ "Dohoda o mlčanlivosti" ] ],
        mandate: [ "Mandátna zmluva – klient Horák", [ "Mandátna zmluva" ] ],
        gdpr: [ "Zmluva o spracúvaní osobných údajov", [ "Zmluva o spracúvaní osobných údajov" ] ],
        settlement: [ "Dohoda o urovnaní", [ "Dohoda o urovnaní" ] ]
      },
      note: "Dobrý deň, posielam zmluvu na podpis. Rozpočet je v prílohe. Ďakujem, Jana Nováková",
      minutes_note: "Prosíme členov predstavenstva o podpis zápisnice do piatku.",
      pdf_body: "Zmluvné strany sa dohodli na nasledujúcich podmienkach. Tento dokument slúži len ako ukážka v používateľskej príručke."
    },
    en: {
      organization: "Novak & Partners Ltd.",
      cooperative: "Rozvoj Housing Cooperative",
      supplier: "Svit Printing Ltd.",
      documents: {
        declaration: "Affidavit",
        power_of_attorney: "Power of attorney",
        invoice: "Invoice 2026-0142",
        leave_request: "Leave request"
      },
      bundles: {
        works: [ "Contract for work – bathroom renovation", [ "Contract for work", "Annex 1 – budget" ] ],
        lease: [ "Lease agreement – flat Hlavna 12", [ "Lease agreement" ] ],
        termination: [ "Termination agreement", [ "Termination agreement" ] ],
        car: [ "Purchase agreement – car", [ "Purchase agreement" ] ],
        minutes: [ "Minutes of the members' meeting", [ "Minutes of the members' meeting" ] ],
        loan: [ "Loan agreement", [ "Loan agreement" ] ],
        order: [ "Print order", [ "Print order" ] ],
        nda: [ "Non-disclosure agreement", [ "Non-disclosure agreement" ] ],
        mandate: [ "Mandate agreement – client Horak", [ "Mandate agreement" ] ],
        gdpr: [ "Data processing agreement", [ "Data processing agreement" ] ],
        settlement: [ "Settlement agreement", [ "Settlement agreement" ] ]
      },
      note: "Hello, please sign the contract. The budget is attached. Thank you, Jana Novakova",
      minutes_note: "Board members, please sign the minutes by Friday.",
      pdf_body: "The parties have agreed on the following terms. This document is only an example for the user guide."
    }
  }.freeze

  I18n.available_locales.each do |locale|
    test "#{locale} screenshots" do
      @locale = locale
      @demo = DEMO.fetch(locale)
      visit "about:blank"
      set_viewport
      install_demo_autogram
      build_demo_data

      screenshot_personal_tenant
      screenshot_received_signing
      screenshot_organization
      assert true
    ensure
      restore_autogram
    end
  end

  private

  # ─── Screens ──────────────────────────────────────────────────────────

  def screenshot_personal_tenant
    sign_in @jana
    visit dashboard_path(locale: @locale)
    assert_current_path tenant_selection_path, ignore_query: true
    capture "tenant-selection", "main > div"

    click_on I18n.t("tenant_selections.show.personal", locale: @locale)
    assert_text I18n.t("dashboard.index.quick_actions.title", locale: @locale)
    capture_window "dashboard"

    visit contracts_path
    assert_text @demo[:documents][:declaration]
    capture "documents", "main > div"

    visit new_contract_path
    capture "document-upload", "main > div"

    visit contract_path(@signed_contract)
    wait_for_frames
    capture "document-detail", "main > div"

    within("turbo-frame#contract_actions_#{@signed_contract.uuid}") do
      click_on I18n.t("documents.new.actions.continue", locale: @locale)
      click_on I18n.t("contracts.signature_parameters.advanced_settings", locale: @locale)
    end
    assert_text I18n.t("contracts.signature_parameters.signature_format", locale: @locale)
    capture "signature-parameters", "turbo-frame#contract_actions_#{@signed_contract.uuid}"

    visit contract_onboarding_path(@unsigned_contract, "qscd_check", method: "electronic")
    capture "qscd-selection", "main > div"

    visit signature_apps_contract_path(@unsigned_contract, qscd: "eid_2024")
    assert_text I18n.t("contracts.signature_apps.title", locale: @locale)
    capture "signing-app-selection", "main turbo-frame"

    visit bundles_path
    capture "bundles", "main > div"

    visit bundle_path(@works_bundle)
    wait_for_frames
    capture "bundle-detail", "main > div"
    capture "bundle-recipients", "main section:has(> turbo-frame[id^='bundle_recipients_'])"

    visit edit_bundle_path(@works_bundle)
    capture "bundle-settings", "main > div"

    visit received_bundles_path
    capture "received", "main > div"

    visit edit_user_registration_path
    capture "settings-account", "section#account"
  end

  def screenshot_received_signing
    visit sign_bundle_path(@minutes_bundle, recipient: @minutes_recipient.uuid)
    wait_for_frames
    capture "bundle-sign", "main > div"
  end

  def screenshot_organization
    Capybara.reset_sessions!
    sign_in @jana
    visit tenant_selection_path(locale: @locale)
    click_on @demo[:organization]
    assert_text I18n.t("dashboard.index.organization.title", locale: @locale)

    visit contract_validation_records_path
    capture "validation-archive", "main > div"

    visit edit_user_registration_path
    capture "settings-organization", "section#organization"
  end

  # ─── Demo data ────────────────────────────────────────────────────────

  def build_demo_data
    @jana = demo_user("jana.novakova@example.com", "Jana Nováková")
    @personal = @jana.tenants.sole

    # A short id, as the API settings print it.
    @organization = Tenant.create!(id: 12, name: @demo[:organization], plan: :pro, features: %w[archivation api])
    @organization.memberships.create!(user: @jana, role: :owner)
    # A second owner, so the account settings show the usual (not blocked) account deletion.
    @organization.memberships.create!(user: demo_user("peter.kovac@example.com", "Peter Kováč"), role: :owner)
    @organization.memberships.create!(user: demo_user("lucia.horvathova@example.com", "Lucia Horváthová"), role: :member)
    @jana.update!(last_tenant: @personal)

    build_personal_documents
    build_personal_bundles
    build_received_bundles
    build_organization_data
  end

  def build_personal_documents
    docs = @demo[:documents]
    @signed_contract = demo_contract(@personal, docs[:declaration], created_at: 2.days.ago).tap(&:save!)
    sign_contract!(@signed_contract, signers: [ "Jana Nováková" ], at: 2.days.ago)
    @unsigned_contract = demo_contract(@personal, docs[:power_of_attorney], created_at: 1.hour.ago).tap(&:save!)
    demo_contract(@personal, docs[:invoice], created_at: 5.days.ago).save!
    leave = demo_contract(@personal, docs[:leave_request], created_at: 12.days.ago).tap(&:save!)
    sign_contract!(leave, signers: [ "Jana Nováková" ], at: 12.days.ago)
  end

  def build_personal_bundles
    bundles = @demo[:bundles]

    @works_bundle = demo_bundle(@personal, *bundles[:works], created_at: 1.day.ago, note: @demo[:note], publicly_visible: false)
    signed = add_recipient(@works_bundle, "martin.simko@example.com")
    add_recipient(@works_bundle, "jana.horvathova@example.com")
    add_recipient(@works_bundle, "eva.kralova@example.com", notified: false)
    add_recipient(@works_bundle, "peter.kollar@example.com", notified: false)
    sign_recipient!(@works_bundle, signed, "Martin Šimko", at: 6.hours.ago)

    lease = demo_bundle(@personal, *bundles[:lease], created_at: 4.days.ago)
    owner = add_recipient(lease, "tomas.balaz@example.com")
    tenant = add_recipient(lease, "zuzana.hruskova@example.com")
    sign_recipient!(lease, owner, "Tomáš Baláž", at: 3.days.ago)
    sign_recipient!(lease, tenant, "Zuzana Hrušková", at: 3.days.ago, signers: [ "Tomáš Baláž", "Zuzana Hrušková" ])

    termination = demo_bundle(@personal, *bundles[:termination], created_at: 7.days.ago)
    decline_recipient!(add_recipient(termination, "robert.kral@example.com"), at: 6.days.ago)

    demo_bundle(@personal, *bundles[:car], created_at: 2.hours.ago)

    @personal.record_signature_requests!(Contract.where(bundle: [ @works_bundle, lease, termination ]), source: :notification, enforce: false)
  end

  def build_received_bundles
    bundles = @demo[:bundles]
    cooperative = Tenant.create!(name: @demo[:cooperative], plan: :pro)
    supplier = Tenant.create!(name: @demo[:supplier], plan: :pro)
    peter = User.find_by!(email: "peter.kovac@example.com")
    peter_personal = peter.tenants.find_by!(plan: :basic)

    @minutes_bundle = demo_bundle(cooperative, *bundles[:minutes], created_at: 3.hours.ago, note: @demo[:minutes_note])
    @minutes_recipient = add_recipient(@minutes_bundle, @jana.email)
    add_recipient(@minutes_bundle, "michal.vrabel@example.com")

    loan = demo_bundle(peter_personal, *bundles[:loan], created_at: 9.days.ago)
    sign_recipient!(loan, add_recipient(loan, @jana.email), "Jana Nováková", at: 8.days.ago)

    order = demo_bundle(supplier, *bundles[:order], created_at: 11.days.ago, signing_rule: "any")
    superseded = add_recipient(order, @jana.email)
    sign_recipient!(order, add_recipient(order, "peter.kovac@example.com"), "Peter Kováč", at: 10.days.ago)
    superseded.signer_contracts.each { |signer_contract| signer_contract.update!(superseded_at: 10.days.ago) }

    nda = demo_bundle(supplier, *bundles[:nda], created_at: 15.days.ago)
    decline_recipient!(add_recipient(nda, @jana.email), at: 14.days.ago)
  end

  def build_organization_data
    bundles = @demo[:bundles]
    mandate = demo_bundle(@organization, *bundles[:mandate], created_at: 1.day.ago)
    add_recipient(mandate, "frantisek.horak@example.com")
    add_recipient(mandate, @jana.email)

    archived = {
      gdpr: [ "maria.kollarova@example.com", "Mária Kollárová", 20.days.ago, 3.years.from_now ],
      settlement: [ "ondrej.matus@example.com", "Ondrej Matúš", 40.days.ago, 45.days.from_now ]
    }
    archived.each do |key, (email, signer_name, signed_at, expires_at)|
      bundle = demo_bundle(@organization, *bundles[key], created_at: signed_at)
      sign_recipient!(bundle, add_recipient(bundle, email), signer_name, at: signed_at, expires_at: expires_at, archive: true)
    end
    @organization.record_signature_requests!(Contract.where(tenant: @organization), source: :notification, enforce: false)
  end

  def demo_user(email, name)
    User.create!(email: email, name: name, confirmed_at: Time.current, locale: @locale.to_s).tap do |user|
      PolicyVersions.current.each do |policy_type, version|
        user.policy_consents.create!(policy_type: policy_type, policy_version: version, source: "email_signup", accepted_at: Time.current)
      end
    end
  end

  def demo_contract(tenant, title, created_at:, allowed_methods: Contract::OWN_SIGNING_DEFAULT_METHODS.dup)
    Contract.new(
      tenant: tenant,
      author_notifications_enabled: true,
      allowed_methods: allowed_methods,
      created_at: created_at,
      documents: [ Document.new(blob: uploaded_pdf(title)) ]
    )
  end

  # Documents read a new upload from its tempfile, as when it comes from the upload form.
  def uploaded_pdf(title)
    tempfile = Tempfile.new([ "user-guide", ".pdf" ], binmode: true)
    tempfile.write(demo_pdf(title))
    tempfile.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, filename: "#{title}.pdf", type: "application/pdf")
  end

  def demo_bundle(tenant, name, titles, created_at:, note: nil, signing_rule: "all", publicly_visible: false)
    Bundle.create!(
      tenant: tenant,
      name: name,
      note: note,
      signing_rule: signing_rule,
      publicly_visible: publicly_visible,
      author_notifications_enabled: true,
      created_at: created_at,
      contracts: titles.map { |title| demo_contract(tenant, title, created_at: created_at, allowed_methods: %w[qes ades]) }
    )
  end

  def add_recipient(bundle, email, notified: true)
    bundle.recipients.create!(email: email, notification_status: notified ? :notified : :not_notified, notified_at: (1.day.ago if notified))
  end

  def sign_recipient!(bundle, recipient, signer_name, at:, signers: [ signer_name ], expires_at: 2.years.from_now, archive: false)
    recipient.signer_contracts.each { |signer_contract| signer_contract.update!(signed_at: at) }
    bundle.contracts.each { |contract| sign_contract!(contract, signers: signers, at: at, expires_at: expires_at, archive: archive) }
  end

  def decline_recipient!(recipient, at:)
    recipient.signer_contracts.each { |signer_contract| signer_contract.update!(declined_at: at) }
  end

  # Stores a signed version of the contract and teaches the fake Autogram how to validate it.
  def sign_contract!(contract, signers:, at:, expires_at: 2.years.from_now, archive: false)
    filename = contract.documents.first.blob.filename.to_s
    content = demo_pdf("#{filename} (#{signers.join(', ')})")
    validation = demo_validation(filename, signers: signers, at: at, expires_at: expires_at)
    @autogram.register_signed(content, validation)
    version = contract.add_signed_content_version!(content: content, filename: filename, content_type: "application/pdf", origin: "signing", created_at: at)
    return unless archive

    ContractValidationRecord.capture!(
      contract: contract,
      contract_content_version: version,
      validation_result: version.validation_result,
      signed_content: content,
      filename: filename
    )
  end

  def demo_validation(filename, signers:, at:, expires_at:)
    {
      "signatureForm" => "PAdES",
      "containerType" => nil,
      "signedObjects" => [ { "id" => "D-1", "filename" => filename, "mimeType" => "application/pdf" } ],
      "unsignedObjects" => [],
      "signatures" => signers.map do |name|
        {
          "validationResult" => "TOTAL_PASSED",
          "level" => "PAdES_BASELINE_B",
          "claimedSigningTime" => at.iso8601,
          "signedObjectsIds" => [ "D-1" ],
          "signingCertificate" => {
            "subjectDN" => "CN=#{name}, C=SK",
            "issuerDN" => "CN=SVK eID ACA2, O=Disig a.s., C=SK",
            "qualification" => "QESIG",
            "notAfter" => expires_at.iso8601
          }
        }
      end
    }
  end

  # A one-page PDF printed by the browser, so the documents look real in previews.
  def demo_pdf(title)
    @demo_pdfs ||= {}
    @demo_pdfs[title] ||= begin
      html = <<~HTML
        <!doctype html><meta charset="utf-8">
        <body style="font-family: Georgia, serif; margin: 64px; color: #111">
          <h1 style="font-size: 26px">#{ERB::Util.html_escape(title)}</h1>
          #{Array.new(6) { "<p style='line-height: 1.6'>#{ERB::Util.html_escape(@demo[:pdf_body])}</p>" }.join}
        </body>
      HTML
      visit "about:blank"
      page.execute_script("document.open(); document.write(arguments[0]); document.close();", html)
      Base64.decode64(page.driver.browser.execute_cdp("Page.printToPDF", printBackground: true)["data"])
    end
  end

  # ─── Capturing ────────────────────────────────────────────────────────

  def install_demo_autogram
    @autogram = DemoAutogramService.new
    service = @autogram
    environment = AutogramEnvironment.singleton_class
    environment.send(:alias_method, :__original_autogram_service, :autogram_service)
    environment.send(:define_method, :autogram_service) { service }
  end

  def restore_autogram
    environment = AutogramEnvironment.singleton_class
    return unless environment.method_defined?(:__original_autogram_service)

    environment.send(:remove_method, :autogram_service)
    environment.send(:alias_method, :autogram_service, :__original_autogram_service)
    environment.send(:remove_method, :__original_autogram_service)
  end

  def wait_for_frames
    assert_no_selector "turbo-frame[busy]", wait: 10
    assert_no_text I18n.t("contracts.signature_validation.validating", locale: @locale), wait: 10
    assert_no_text I18n.t("bundles.show.loading_recipients", locale: @locale), wait: 10
  end

  # Saves the content of the element matching +selector+ with an even margin around it, without
  # animations, focus rings or hover states.
  def capture(name, selector, margin: 24)
    element = find(selector, match: :first)
    prepare_page
    rect = page.evaluate_script(<<~JS, element, margin)
      (function(root, margin) {
        // Only what paints something counts, so padding of layout wrappers does not widen the image.
        const paints = (el, style) => {
          if (["IMG", "INPUT", "BUTTON", "SELECT", "TEXTAREA", "CANVAS", "IFRAME"].includes(el.tagName) || el instanceof SVGSVGElement) return true;
          if (!["rgba(0, 0, 0, 0)", "transparent"].includes(style.backgroundColor) || style.backgroundImage !== "none") return true;
          if (["Top", "Right", "Bottom", "Left"].some((side) => parseFloat(style["border" + side + "Width"]) > 0 && style["border" + side + "Style"] !== "none")) return true;
          return Array.from(el.childNodes).some((node) => node.nodeType === Node.TEXT_NODE && node.textContent.trim() !== "");
        };
        let box = null;
        for (const el of [root, ...root.querySelectorAll("*")]) {
          if (el.closest("svg") && !(el instanceof SVGSVGElement)) continue;
          const style = getComputedStyle(el);
          const r = el.getBoundingClientRect();
          if (style.visibility === "hidden" || r.width <= 1 || r.height <= 1 || !paints(el, style)) continue;
          box = box ? { left: Math.min(box.left, r.left), top: Math.min(box.top, r.top), right: Math.max(box.right, r.right), bottom: Math.max(box.bottom, r.bottom) } : { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
        }
        const x = Math.max(0, box.left + window.scrollX - margin);
        const y = Math.max(0, box.top + window.scrollY - margin);
        return { x: x, y: y, width: box.right + window.scrollX + margin - x, height: box.bottom + window.scrollY + margin - y };
      })(arguments[0], arguments[1])
    JS
    save_screenshot_clip(name, rect)
  end

  # Saves the whole window with the navigation. The viewport is as tall as the main content (or the
  # navigation, if longer), so the items at the bottom of the navigation are in the picture too.
  def capture_window(name)
    prepare_page
    height = page.evaluate_script(<<~JS)
      (function() {
        const content = document.querySelector("main").firstElementChild.getBoundingClientRect().bottom + window.scrollY;
        const nav = document.querySelector("header nav");
        const navigation = Array.from(nav.children).reduce((sum, child) => sum + child.getBoundingClientRect().height, 0) + 160;
        return Math.ceil(Math.max(content + 24, navigation));
      })()
    JS
    set_viewport(height: height)
    save_screenshot_clip(name, { "x" => 0, "y" => 0, "width" => WINDOW_WIDTH, "height" => height })
  ensure
    set_viewport
  end

  def set_viewport(height: VIEWPORT_HEIGHT)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: WINDOW_WIDTH, height: height, deviceScaleFactor: 2, mobile: false)
  end

  def prepare_page
    page.execute_script(<<~JS)
      if (!document.getElementById("user-guide-screenshot-style")) {
        const style = document.createElement("style");
        style.id = "user-guide-screenshot-style";
        style.textContent = "*, *::before, *::after { transition: none !important; animation: none !important; caret-color: transparent !important; } .turbo-progress-bar { display: none !important; }";
        document.head.appendChild(style);
      }
      document.activeElement && document.activeElement.blur();
      window.scrollTo(0, 0);
    JS
    page.driver.browser.action.move_to_location(0, 0).perform
  end

  # WebP keeps the 2x images sharp at a fraction of the PNG size.
  def save_screenshot_clip(name, rect)
    clip = rect.transform_keys(&:to_s).slice("x", "y", "width", "height").transform_values { |value| value.to_f.round }
    data = page.driver.browser.execute_cdp("Page.captureScreenshot", format: "webp", quality: 90, captureBeyondViewport: true, clip: clip.merge("scale" => 1))["data"]
    path = OUTPUT_DIR.join(@locale.to_s, "#{name}.webp")
    FileUtils.mkdir_p(path.dirname)
    File.binwrite(path, Base64.decode64(data))
    puts "saved #{path.relative_path_from(Rails.root)}"
  end
end
