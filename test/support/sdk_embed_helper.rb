require_relative "signing_flow_helper"

# Helpers for system tests of the JavaScript SDK (/sdk.js) that integrators use to
# open bundles and contracts in an iframe or popup on their own pages
# (see public/sdk-example.html).
#
# The integrator page is served from http://localhost:<port> while the SDK and the
# portal run on http://127.0.0.1:<port>, so the portal is embedded cross-site as it
# is at a real integrator: the portal's cookies are not sent to the iframe and
# messages cross origins. Pass same_site: true to serve the integrator page from
# the portal's host instead.
module SdkEmbedHelper
  INTEGRATOR_PAGE_PATH = "/__integrator_page".freeze

  # Stands in for the HTTP API of the Autogram desktop app (http://localhost:37200), so the
  # portal's Autogram signers run the real vendored autogram-sdk.js against it. With a signed
  # result they get a file SigningFlowHelper::FakeAutogramService accepts as validly signed,
  # otherwise one without signatures. The last sign request is kept as the app receives it,
  # see #last_autogram_sign_request.
  # version is the Autogram version the app reports: before 2.8.0 it has only the legacy POST /sign
  # for one document, from 2.8.0 also POST /api/v1/sign. With running: false the app is not started
  # until the signer clicks in the page (a click lets the page launch it), with cancel_first_batch: true
  # the signer cancels the first batch in it, with skip_document: n the signer skips the n-th document
  # the app is asked to sign (Autogram 2.9 answers it like a cancelled signing).
  def self.fake_autogram_app(signed:, version: "2.9.0", running: true, cancel_first_batch: false, skip_document: nil)
    prefix = signed ? SigningFlowHelper::SIGNED_PREFIX : "unsigned:"

    <<~JS
      (() => {
        const count = (key) => {
          const value = Number(sessionStorage.getItem(key) || 0) + 1;
          sessionStorage.setItem(key, value);
          return value;
        };
        const respond = (body, status = 200) =>
          new Response(body === null ? null : JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
        const versionSupportsSignV1 = #{Gem::Version.new(version) >= Gem::Version.new("2.8.0")};
        const appFetch = async (url, init) => {
          if (!#{running} && !navigator.userActivation?.hasBeenActive) throw new TypeError("Failed to fetch");

          const route = `${(init?.method || "GET").toUpperCase()} ${url.pathname}`;
          if (route === "GET /info") return respond({ status: "READY", version: #{version.to_json} });
          if (route === "POST /batch") {
            return #{cancel_first_batch} && count("fakeAutogramBatchStarts") === 1 ? respond(null, 204) : respond({ batchId: "fake-batch" });
          }
          if (route === "DELETE /batch") return respond({});
          if (route === "POST /sign" || (route === "POST /api/v1/sign" && versionSupportsSignV1)) {
            if (count("fakeAutogramSignCalls") === #{skip_document.to_json}) return respond(null, 204);

            const body = JSON.parse(init.body);
            sessionStorage.setItem("fakeAutogramSignRequest", JSON.stringify({ path: url.pathname, body }));
            const filenames = (body.documents || [ body.document ]).map((document) => document.filename || "document");
            return respond({ content: btoa("#{prefix}" + filenames.join(",")), signedBy: "CN=Fake Signer", issuedBy: "CN=Fake CA" });
          }
          return respond({ code: "NOT_FOUND" }, 404);
        };

        const fetch = window.fetch.bind(window);
        window.fetch = (input, init) => {
          const url = new URL(input instanceof Request ? input.url : String(input), location.href);
          if (url.origin === "http://localhost:37200") return appFetch(url, init);
          return fetch(input, init);
        };
      })();
    JS
  end

  # Serves a minimal integrator page in front of the application. Messages the
  # SDK passes to onMessage are listed in #agp-messages with the id of the SDK
  # instance that received them, onClose calls are counted in #agp-close-count.
  class IntegratorPage
    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless env["PATH_INFO"] == INTEGRATOR_PAGE_PATH

      [ 200, { "content-type" => "text/html; charset=utf-8" }, [ html(env["SERVER_PORT"]) ] ]
    end

    private

    def html(port)
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
          <head><meta charset="utf-8"><title>Integrator</title></head>
          <body>
            <h1>Integrator page</h1>
            <div id="agp-container"></div>
            <ol id="agp-messages"></ol>
            <p id="agp-close-count">0</p>
            <script>
              window.agpReceive = (instance, data) => {
                const item = document.createElement("li");
                item.dataset.instance = instance;
                item.dataset.status = data.status;
                item.textContent = JSON.stringify(data);
                document.getElementById("agp-messages").appendChild(item);
              };
              window.agpClosed = () => {
                const counter = document.getElementById("agp-close-count");
                counter.textContent = Number(counter.textContent) + 1;
              };
            </script>
            <script src="http://127.0.0.1:#{port}/sdk.js"></script>
          </body>
        </html>
      HTML
    end
  end

  def self.included(base)
    # Fakes Autogram validation and provides the data helpers; its setup runs first.
    base.include SigningFlowHelper

    # The fake Autogram app is injected into the portal frame before its scripts
    # run, which Chrome only does for frames in the integrator page's process.
    # Cookies and origins stay cross-site.
    base.driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ], options: { name: :headless_chrome_shared_frame_process } do |options|
      options.add_argument("--disable-site-isolation-trials")
      options.add_argument("--disable-features=IsolateOrigins,site-per-process")
    end

    base.setup do
      Capybara.app = IntegratorPage.new(Capybara.app) unless Capybara.app.is_a?(IntegratorPage)
      # The SDK and the Autogram parameters build URLs from the request host.
      Rails.application.config.action_controller.default_url_options = {}
      # The portal runs with CSRF protection in production; the signing JavaScript needs its token.
      @original_allow_forgery_protection = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
    end

    base.teardown do
      ActionController::Base.allow_forgery_protection = @original_allow_forgery_protection
      if @fake_autogram_app_script
        page.driver.browser.execute_cdp("Page.removeScriptToEvaluateOnNewDocument", identifier: @fake_autogram_app_script)
      end
    end
  end

  # Opens the integrator page and calls the SDK the way integrators do, e.g.
  #   embed_with_sdk :initBundleIframe, bundle.uuid, parentElement: "#agp-container", recipientId: recipient.uuid
  # Returns the iframe the SDK created.
  def embed_with_sdk(method, id, same_site: false, **options)
    visit_integrator_page(same_site: same_site)
    call_sdk(method, id, **options)
  end

  def visit_integrator_page(same_site: false)
    integrator_host = same_site ? "127.0.0.1" : "localhost"
    visit "http://#{integrator_host}:#{Capybara.current_session.server.port}#{INTEGRATOR_PAGE_PATH}"
    assert_selector "h1", text: "Integrator page"
  end

  def call_sdk(method, id, **options)
    page.execute_script(<<~JS, method.to_s, id, options.stringify_keys)
      const [method, id, options] = arguments;
      window.agpInstance = window.agp[method](id, Object.assign({}, options, {
        onMessage: (data) => window.agpReceive(id, data),
        onClose: () => window.agpClosed()
      }));
    JS

    find("iframe[data-agp-session='#{id}']")
  end

  # Runs the block inside the embedded portal (the one opened for +id+ when there are several).
  def within_portal_frame(id = nil, &block)
    within_frame(find(id ? "iframe[data-agp-session='#{id}']" : "iframe[data-agp-session]"), &block)
  end

  # Makes Autogram signing in the portal produce a signed (or unsigned) file for
  # the pages opened afterwards.
  def install_fake_autogram_app(signed: true, **options)
    @fake_autogram_app_script = page.driver.browser.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: SdkEmbedHelper.fake_autogram_app(signed: signed, **options))["identifier"]
  end

  # How many batches the fake Autogram app was asked to start. Call it within the portal frame.
  def autogram_batch_starts
    page.evaluate_script("Number(sessionStorage.getItem('fakeAutogramBatchStarts') || 0)")
  end

  # How many sign requests the fake Autogram app received. Call it within the portal frame.
  def autogram_sign_calls
    page.evaluate_script("Number(sessionStorage.getItem('fakeAutogramSignCalls') || 0)")
  end

  # The last sign request the fake Autogram app answered: its path ("/api/v1/sign", or the
  # legacy "/sign") and its JSON body. Call it within the portal frame.
  def last_autogram_sign_request
    JSON.parse(page.evaluate_script("sessionStorage.getItem('fakeAutogramSignRequest')") || "null")
  end

  # Waits for the integrator page to receive a portal message with +status+
  # (through the SDK instance opened for +to+, if given) and returns it.
  def assert_portal_message(status, to: nil)
    instance_filter = "[data-instance='#{to}']" if to
    message = find("#agp-messages li[data-status='#{status}']#{instance_filter}")
    JSON.parse(message.text)
  end
end
