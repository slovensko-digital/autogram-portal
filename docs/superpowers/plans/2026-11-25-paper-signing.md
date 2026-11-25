# Paper Signing ("Podpis na papieri") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recipients of a bundle can sign a PDF on paper and upload a scan or phone photos; a member of the sending organization approves the scan (the recipient then counts as signed) or returns it with a reason; the legacy "physical" flow is removed.

**Architecture:** A new `PaperSignature` model (with ordered `PaperSignaturePage`s) belongs to a `SignerContract`; approval goes through a completion method extracted from `Session` so paper and electronic signatures complete bundles identically. Signer pages live under the contract (`Contracts::PaperSignatures…`), the review under the bundle (`Bundles::PaperSignatures…`), the API exposes `paper_signatures` on contracts.

**Tech Stack:** Rails 8, Minitest, Pundit, Hotwire (Turbo, Stimulus), Tailwind v4, new gems `prawn` (photos → PDF), `pdf-reader` (page counts), `rqrcode` (QR SVG).

**Spec:** `docs/superpowers/specs/2026-11-25-paper-signing-design.md` (read it first; screens referenced as "screen N" are in Figma, file key `ibhM3spNhwjqFVv2GaOb9D`, page "Obrazovky", sections "Podpis na papieri – návrh (…)").

## Global Constraints

- Allowed-method key stays `scan` (ENV `ALLOWED_METHODS`, `contracts.allowed_methods`, API `allowedMethods`); the internal signing-method name offered to signers is `paper`.
- Paper signing is offered only to an active, visible (not author proxy), non-federated recipient, outside iframes (`params[:iframe]` blank), for a contract with exactly one document that is a PDF, when `allowed_methods` include `scan`.
- A scan never becomes a `ContractContentVersion`; only an `approved` paper signature counts as a signature.
- Scans and page images are served only through authorized controller actions (`send_data`), never `rails_blob_url`.
- Every user-facing string in `config/locales/sk.yml` and `en.yml` with identical keys; Slovak copy below is fixed by the screens.
- Commit as the repository user, messages lowercase sentences like the existing history ("answer not found instead of …"), no attribution trailers.
- After schema changes run `bin/rails db:migrate && bundle exec annotaterb models`; keep `bin/rubocop`, `bin/brakeman`, `bin/rails zeitwerk:check` clean.
- Run tests with an isolated DB: `export DATABASE_URL=postgres:///agp_test_paper_signing` and once `bin/rails db:create db:schema:load` (RAILS_ENV=test).

### Fixed Slovak copy (screens 1–11)

| Key purpose | sk |
| --- | --- |
| Method label / description (signer) | „Podpis na papieri“ / „Vytlačte dokument, podpíšte ho perom a nahrajte sken alebo fotky“ |
| Method label / description (author, `contracts.allowed_methods.short.scan` / `.scan`) | „Podpis na papieri“ / „Podpisujúci dokument vytlačí, podpíše perom a nahrá sken alebo fotky. Podpis potom skontrolujete vy.“ |
| Page title / intro | „Podpis na papieri“ / „Vytlačte dokument, podpíšte ho perom a nahrajte sken alebo fotky strán. Podpis potom skontroluje odosielateľ, %{sender}.“ |
| Back link | „Späť na výber spôsobu podpisu“ |
| Steps | „Stiahnite a vytlačte dokument“ (button „Stiahnuť na tlač“) · „Podpíšte ho perom“ (text „Podpíšte dokument vlastnou rukou na miestach určených na podpis a doplňte, čo sa na nich vypĺňa (napríklad dátum).“) · „Nahrajte sken alebo fotky strán“ |
| Dropzone | „Pretiahnite sem sken alebo fotky strán“ / „alebo kliknite a vyberte súbory“ / „PDF zo skenera alebo fotky (JPG, PNG, HEIC)“ |
| QR panel | „Odfoťte strany mobilom“ / „Naskenujte kód fotoaparátom mobilu. Odfotené strany sa tu zobrazia samé.“ |
| Page tile / add | „Strana %{number}“ / „Pridať stranu“ |
| Page count warning | „Dokument má %{expected} strany, nahrali ste %{actual}“ / „Nahrajte všetky strany, aby odosielateľ videl celý podpísaný dokument. Odoslať ho môžete aj tak.“ (use i18n pluralization) |
| Submit | „Odoslať na kontrolu“ |
| Submitted | „Sken sme odoslali na kontrolu“ / „%{sender} skontroluje, či je dokument podpísaný. Keď podpis schváli alebo vráti, pošleme vám e-mail na %{email}.“ · card „Nahratý sken“ · „Nahrať iný sken“ |
| Discard (not drawn) | „Zahodiť sken a podpísať inak“ |
| Phone page | „Odfoťte podpísané strany“ · „Odfotiť ďalšiu stranu“ · „Vybrať z galérie“ · „Odoslať na kontrolu (%{count} strany)“ |
| Returned | „Odosielateľ vrátil váš sken“ / reason / „Vrátil(a) %{name} %{time}“ |
| Recipient badge | `helpers.recipients.status.awaiting_review`: „Čaká na kontrolu skenu“ (blue: `bg-blue-100 text-blue-800`) |
| Bundle alert | „%{name} nahral(a) sken podpísaného dokumentu“ / „Skontrolujte ho, aby sa jeho podpis započítal.“ · button „Skontrolovať sken“ |
| Review page | „Kontrola podpisu na papieri“ · info „Portál nevie overiť, či je na skene naozaj podpis“ / „Porovnajte nahraté strany s pôvodným dokumentom. Po schválení sa podpis započíta a balík sa môže dokončiť.“ · columns „Pôvodný dokument“ / „Nahraný sken“ · „Je dokument podpísaný?“ / „Schválením sa podpis započíta. Ak niečo chýba, vráťte sken s dôvodom.“ · „Vrátiť sken“ · „Schváliť podpis“ |
| Return dialog | „Vrátiť sken“ (title with name) · „%{name} dostane e-mail s vaším dôvodom a môže nahrať nový sken. Jeho podpis sa nezapočíta, kým neschválite nový sken.“ · label „Dôvod“ · hint „Dôvod uvidí v e-maile aj na stránke podpisu.“ · „Zrušiť“ |
| After approval | „Podpis na papieri · schválil(a) %{name} %{time}“ · „Stiahnuť sken“ |
| Validation box | „Podpis na papieri“, name, date, „overené odosielateľom“ |
| No longer needed | reuse `bundles.sign.signature_no_longer_required` |

## Review Focus

- The same recipient opens the paper page on the computer and the phone at once: exactly one open (draft/submitted) paper signature per signer contract (partial unique index), the second request reuses it — test in Task 4 and Task 6.
- A scan larger than `PlanLimits.max_document_bytes` after combining: the signer sees a validation message, nothing is submitted, no 500 — test in Task 4.
- A non-image, non-PDF upload (e.g. `.docx`, or HEIC a desktop browser did not convert): rejected with a message, the draft stays usable — test in Task 6.
- Approve or return on a paper signature whose recipient was meanwhile withdrawn, superseded or that was already reviewed (double click, two reviewers): refused with `bundles.sign.signature_no_longer_required`-style notice, no second completion — test in Task 9.
- A phone link used after expiry, after submit, or for another contract: friendly error page, no change — test in Task 7.

---

### Task 1: Shared signature completion

Extract the completion now inside `Session` so paper approval can reuse it, and let the person who caused the completion be excluded from author mails.

**Files:**
- Modify: `app/models/signer_contract.rb`, `app/models/session.rb:267-286` (`handle_status_change`, `mark_signer_contract_signed`, `broadcast_status_change` signed branch), `app/models/contract.rb:170-176` (`notify_signed!`), `app/models/bundle.rb:140-156` (`notify_contract_signed`), `app/jobs/notification/bundle_contract_signed_job.rb`, `bundle_completed_job.rb`, `contract_signed_job.rb`
- Test: `test/models/signer_contract_test.rb`, `test/integration/signature_request_flows_test.rb`

**Interfaces:**
- Produces: `SignerContract#complete_signature!(at: Time.current, except: signing_user) -> void` — sets `signed_at` (update_column), calls `contract.record_signature_request_on_signing!(signing_user)` and `contract.notify_signed!(signer: signer, except: except)`.
- Produces: `Contract#notify_signed!(signer: nil, except: signer&.user)`, `Bundle#notify_contract_signed(contract, signer, except: signer&.user)`; the three jobs take `except:` and pass it to `Tenant#notification_recipients(except:)`.

- [ ] **Step 1: Write the failing tests**

```ruby
# test/models/signer_contract_test.rb
test "completing a signature marks it signed and counts the signature request" do
  # bundle of a PRO tenant with one notified recipient, its RecipientSigner and SignerContract
  signer_contract.complete_signature!(at: Time.zone.parse("2026-11-25 15:02"))
  assert_equal Time.zone.parse("2026-11-25 15:02"), signer_contract.reload.signed_at
  assert bundle.reload.completed?
  assert_equal 1, UsageRecord.signature_request.where(contract: contract).count
end

# test/integration/signature_request_flows_test.rb
test "whoever completes a bundle for a recipient gets no completion mail" do
  # bundle with author_notifications_enabled, author @owner, one recipient
  perform_enqueued_jobs { recipient_signer_contract.complete_signature!(except: @owner) }
  assert_empty mails_to(@owner.email).select { |m| m.subject == I18n.t("notification_mailer.bundle_completed.subject") }
end
```

- [ ] **Step 2: Run** `bin/rails test test/models/signer_contract_test.rb test/integration/signature_request_flows_test.rb` — Expected: FAIL, `NoMethodError: undefined method 'complete_signature!'`.
- [ ] **Step 3: Implement** `complete_signature!` and the `except:` keyword chain; make `Session#handle_status_change` call `signer_contract.complete_signature!(at: completed_at || Time.current)` when signed and drop `contract.notify_signed!` from `broadcast_status_change` (keep the session's own `broadcast_replace_to`). Delete `mark_signer_contract_signed`.
- [ ] **Step 4: Run** the two files plus `test/models/session_test.rb test/controllers/contracts/sessions_controller_test.rb test/integration` — Expected: all PASS.
- [ ] **Step 5: Commit** `git commit -m "complete a signature in one place so other signing methods can reuse it"`

### Task 2: Remove the legacy physical signing

**Files:**
- Delete: `app/models/physical_session.rb`, `app/views/contracts/physical_signing.html.erb`, `app/views/contracts/onboarding/physical_instructions.html.erb`
- Modify: `app/controllers/contracts_controller.rb` (`:physical_signing`/`:create_physical_session` from every callback list at :4–:14, actions at :148–149 and :160–172, `ensure_onboarding` branch :448–449), `app/controllers/contracts/onboarding_controller.rb` (VALID_STEPS, `handle_physical_instructions`, `redirect_to_next_page`/`first_step` branches, `validate_method_param` → only `electronic`), `config/routes.rb:106-107`, `app/views/contracts/_signing_method_choice.html.erb` (physical radio, hidden link, `physical` in the default-checked conditions), `app/javascript/controllers/signing_method_controller.js` (`physicalButton`), locales sk/en (`contracts.onboarding.physical_title`, `contracts.onboarding.physical_instructions`, `contracts.signing_method_choice.physical_*`, `contracts.physical_signing`), `docs/authorization.md:169` (drop the two actions), `public/openapi.yaml` SignatureMethod enum (remove stale `paper`)
- Create: `db/migrate/<timestamp>_delete_physical_sessions.rb` (`execute "DELETE FROM sessions WHERE type = 'PhysicalSession'"`, irreversible down no-op)
- Test: `test/controllers/contracts_controller_test.rb`, `test/controllers/contracts/onboarding_controller_test.rb`

**Interfaces:** Produces: no `physical` signing method anywhere; `Contract#signing_methods_for` no longer returns `"physical"` (Task 5 adds `"paper"`).

- [ ] **Step 1: Write the failing tests**

```ruby
test "the legacy physical signing pages are gone" do
  assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/contracts/x/physical_signing") }
end

test "the signing method choice no longer offers physical signing" do
  with_allowed_methods(%w[qes scan]) do
    get sign_contract_path(contract_allowing(%w[qes scan]))
    assert_select "input[value=physical]", count: 0
  end
end

test "onboarding for the physical method sends the signer back to the document" do
  get contract_onboarding_path(contract, "physical_instructions", method: "physical")
  assert_redirected_to sign_contract_path(contract, iframe: nil)
end
```

- [ ] **Step 2: Run** the two test files — Expected: FAIL (route recognized, radio present, onboarding renders).
- [ ] **Step 3: Delete and edit** the listed files; add the migration; run `bin/rails db:migrate && bundle exec annotaterb models`.
- [ ] **Step 4: Run** `bin/rails test` and `bin/rails zeitwerk:check` — Expected: PASS. Existing API tests using `with_allowed_methods(%w[qes scan])` only to get a second method must still pass; if one depended on the physical card, switch it to `ades`.
- [ ] **Step 5: Commit** `git commit -m "remove the physical signing that never completed a signature"`

### Task 3: Scan assembly and page counting

**Files:**
- Modify: `Gemfile`/`Gemfile.lock` (`bundle add prawn pdf-reader rqrcode`)
- Create: `app/services/paper_scan.rb`, fixture images `test/fixtures/files/paper-page.jpg` (about 600×800) and `paper-page.png` (small, with alpha)
- Test: `test/services/paper_scan_test.rb`

**Interfaces:**
- Produces: `PaperScan.combine(images) -> String` — `images` is an Array of `[bytes, content_type]` with `image/jpeg` or `image/png`; returns PDF bytes, one page per image, each image fit centered on an A4 page.
- Produces: `PaperScan.page_count(pdf_bytes) -> Integer | nil` — nil when the bytes are not a readable PDF (test PDFs like `"%PDF-1.4 x"` are not).
- Produces: `PaperScan::IMAGE_TYPES = %w[image/jpeg image/png]`, `PaperScan::PDF_TYPE = "application/pdf"`.

- [ ] **Step 1: Write the failing tests**

```ruby
test "photos are combined into one PDF page each, in order" do
  pdf = PaperScan.combine([ [ file_fixture("paper-page.jpg").binread, "image/jpeg" ], [ file_fixture("paper-page.png").binread, "image/png" ] ])
  assert pdf.start_with?("%PDF")
  assert_equal 2, PaperScan.page_count(pdf)
end

test "the page count of something that is not a readable PDF is unknown" do
  assert_nil PaperScan.page_count("%PDF-1.4 zmluva.pdf")
end
```

- [ ] **Step 2: Run** `bin/rails test test/services/paper_scan_test.rb` — Expected: FAIL, `NameError: uninitialized constant PaperScan`.
- [ ] **Step 3: Implement** with `Prawn::Document.new(page_size: "A4", margin: 0)` and `image StringIO, fit:, position: :center, vposition: :center`, one `start_new_page` between images; `page_count` with `PDF::Reader.new(StringIO.new(bytes)).page_count` rescuing `PDF::Reader::MalformedPDFError` and `PDF::Reader::UnsupportedFeatureError`.
- [ ] **Step 4: Run** the test — Expected: PASS. (Licenses: prawn Ruby/GPL, pdf-reader MIT, rqrcode MIT — compatible with EUPL 1.2.)
- [ ] **Step 5: Commit** `git commit -m "combine photos of signed pages into one PDF"`

### Task 4: PaperSignature model

**Files:**
- Create: migration `create_paper_signatures` (`signer_contract` ref, `uuid` string not null unique, `status` string not null default "draft", `submitted_at`, `reviewed_at`, `reviewed_by_id` → users `on_delete: :nullify`, `return_reason` text, timestamps; partial unique index on `signer_contract_id` where `status IN ('draft','submitted')`) and `create_paper_signature_pages` (`paper_signature` ref, `position` integer not null, timestamps)
- Create: `app/models/paper_signature.rb`, `app/models/paper_signature_page.rb`
- Modify: `app/models/signer_contract.rb` (`has_many :paper_signatures, dependent: :destroy`), `app/models/contract.rb` (`has_many :paper_signatures, through: :signer_contracts`), `app/models/tenant/usage.rb:90-97` (`storage_bytes` adds `PaperSignature#scan` and `PaperSignaturePage#file` attachments of the tenant's contracts), `app/models/bundle.rb:209-234` (`supersede_pending_recipients!`), `app/models/recipient.rb:217-231` (`withdraw!`), `app/controllers/bundles_controller.rb:192-198` (decline) — each cancels open paper signatures of the affected signer contracts
- Test: `test/models/paper_signature_test.rb`, `test/models/tenant/usage_test.rb`

**Interfaces:**
- Produces: `PaperSignature` — `enum :status, { draft: "draft", submitted: "submitted", approved: "approved", returned: "returned", canceled: "canceled" }`; scope `open` (draft or submitted); `has_many :pages, -> { order(:position) }, class_name: "PaperSignaturePage", dependent: :destroy`; `has_one_attached :scan`; `belongs_to :reviewed_by, class_name: "User", optional: true`; delegates `contract`, `signer`, `recipient` to `signer_contract`.
- Produces: `PaperSignature.open_for!(signer_contract) -> PaperSignature` (find the open one or create a draft; rescues `ActiveRecord::RecordNotUnique` by finding again).
- Produces: `#add_pages!(files) -> Array<PaperSignaturePage>` (files are `ActionDispatch::Http::UploadedFile`/`Rack::Test::UploadedFile`; accepts `PaperScan::IMAGE_TYPES`, or one PDF which then replaces all pages; raises `PaperSignature::InvalidUpload` with an i18n message otherwise), `#remove_page!(page)`, `#move_page!(page, position)`.
- Produces: `#expected_page_count -> Integer | nil` (of the contract's source PDF via `PaperScan.page_count`), `#uploaded_page_count -> Integer | nil` (images count, or the PDF's page count).
- Produces: `#submit! -> void` (draft with pages only; builds `scan` via `PaperScan.combine` or the uploaded PDF; raises `PaperSignature::InvalidUpload` when the scan exceeds `PlanLimits.max_document_bytes`; sets `submitted_at`). Emails are added in Task 10.
- Produces: `PaperSignature::InvalidUpload` messages from `paper_signatures.errors.unsupported_file` and `paper_signatures.errors.too_large`; `#to_param` returns `uuid` (generated on create with `SecureRandom.uuid`).
- Produces: `#approve!(reviewer) -> void` (submitted and signer contract awaiting only, else raises `PaperSignature::NoLongerReviewable`; sets reviewed fields, `approved`, then `signer_contract.complete_signature!(at: reviewed_at, except: reviewer)`).
- Produces: `#return!(reviewer, reason) -> void` (same guard; reason required → `ActiveRecord::RecordInvalid`).
- Produces: `#cancel! -> void` (open only; no-op otherwise). Every state change `broadcast_refresh_to(self)` and `broadcast_refresh_to(contract)`; leaving `submitted` purges page files.
- Produces: `PaperSignaturePage` — `belongs_to :paper_signature`, `has_one_attached :file`, `#image?`, `#pdf?`.

- [ ] **Step 1: Write the failing tests** (`test/models/paper_signature_test.rb`; build a PRO tenant bundle with a single real PDF from `Prawn::Document.new { text "a"; start_new_page; text "b" }.render` and one recipient)

```ruby
test "a signer contract has one open paper signature" do
  assert_equal PaperSignature.open_for!(signer_contract), PaperSignature.open_for!(signer_contract)
end

test "submitting photos stores one combined scan and approval signs the recipient" do
  paper = PaperSignature.open_for!(signer_contract)
  paper.add_pages!([ jpeg_upload, jpeg_upload ])
  paper.submit!
  assert paper.submitted?
  assert_equal 2, PaperScan.page_count(paper.scan.download)
  paper.approve!(reviewer)
  assert recipient.reload.signed?
  assert_equal reviewer, paper.reload.reviewed_by
end

test "a returned scan keeps its reason and leaves the recipient pending" do
  paper = submitted_paper_signature
  paper.return!(reviewer, "Na strane 2 chýba podpis.")
  assert paper.returned?
  assert recipient.reload.pending?
end

test "returning needs a reason" do
  assert_raises(ActiveRecord::RecordInvalid) { submitted_paper_signature.return!(reviewer, "") }
end

test "a scan over the document size limit is not submitted" do
  with_plan_limits("MAX_DOCUMENT_SIZE_MB" => "0.001") do
    paper = PaperSignature.open_for!(signer_contract)
    paper.add_pages!([ jpeg_upload ])
    assert_raises(PaperSignature::InvalidUpload) { paper.submit! }
    assert paper.reload.draft?
  end
end

test "an uploaded PDF replaces photos and is the scan as it is" do
  paper = PaperSignature.open_for!(signer_contract)
  paper.add_pages!([ jpeg_upload ])
  paper.add_pages!([ pdf_upload(pages: 2) ])
  assert_equal 1, paper.pages.count
  assert_equal 2, paper.uploaded_page_count
end

test "withdrawing the recipient cancels the open paper signature and it can no longer be approved" do
  paper = submitted_paper_signature
  recipient.withdraw!
  assert paper.reload.canceled?
  assert_raises(PaperSignature::NoLongerReviewable) { paper.approve!(reviewer) }
end

test "a superseded signer contract's scan is canceled" # threshold "any" met by another recipient → canceled
test "a declined bundle cancels the recipient's open scan" # via post decline_bundle_path in an integration test
```

Usage test: `storage_bytes` grows by the scan's byte size after `submit!`.

- [ ] **Step 2: Run** the model tests — Expected: FAIL (`uninitialized constant PaperSignature`).
- [ ] **Step 3: Implement** migrations, models and the cancel hooks (`PaperSignature.open.where(signer_contract_id: ids).find_each(&:cancel!)` next to the existing `Session.pending … canceled!` calls); run `bin/rails db:migrate && bundle exec annotaterb models`.
- [ ] **Step 4: Run** the model, usage and `test/integration/signature_request_flows_test.rb` tests — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "keep paper signatures with their pages, scan and review"`

### Task 5: Offer "Podpis na papieri"

**Files:**
- Modify: `app/models/contract.rb:155-162` (`signing_methods_for`), `app/helpers/signing_helper.rb:29-33` (pass `embedded: true`), `app/views/contracts/_signing_method_choice.html.erb` (paper card with the printer icon, hidden link to Task 6's page, `embedded: params[:iframe].present?`), `app/views/shared/_radio_button_card.html.erb` (add `icon == 'printer'`, heroicons outline printer path, `w-6 h-6 text-gray-700`), `app/javascript/controllers/signing_method_controller.js` (`paperButton` target), locales (`contracts.signing_method_choice.paper_label/paper_description`, `contracts.allowed_methods.scan` and `.short.scan` per the copy table), `docs.index…allowed_methods_note` if it mentions scanning
- Test: `test/models/contract_test.rb`, `test/controllers/bundles_controller_test.rb` (or a new `test/integration/paper_signing_test.rb` used by Tasks 5–9)

**Interfaces:**
- Consumes: nothing new.
- Produces: `Contract#signing_methods_for(recipient: nil, embedded: false) -> Array<String>` with `"paper"` after `"ades"`; `Contract#paper_signing_available_for?(recipient, embedded: false) -> Boolean`.

- [ ] **Step 1: Write the failing tests**

```ruby
test "paper signing is offered to a bundle recipient when the author allowed scans" do
  assert_includes contract.signing_methods_for(recipient: recipient), "paper"
end

test "paper signing is not offered in embedded signing, to the author proxy, to federated recipients or for several documents" do
  assert_not_includes contract.signing_methods_for(recipient: recipient, embedded: true), "paper"
  assert_not_includes contract.signing_methods_for(recipient: author_proxy), "paper"
  assert_not_includes contract.signing_methods_for(recipient: federated_recipient), "paper"
  assert_not_includes asice_contract.signing_methods_for(recipient: its_recipient), "paper"
  assert_not_includes contract.signing_methods_for(recipient: nil), "paper"
end

# integration
test "the recipient picks Podpis na papieri on the bundle signing page" do
  get sign_bundle_path(bundle, recipient: recipient.uuid)
  assert_select "input[value=paper]"
  assert_select "a[href=?]", contract_paper_signature_path(contract, recipient: recipient.uuid)
end
```

- [ ] **Step 2: Run** — Expected: FAIL (`"paper"` missing; route helper undefined until Task 6 — write the integration assertion with a literal path `"/contracts/#{contract.uuid}/paper_signature?recipient=#{recipient.uuid}"` and switch to the helper in Task 6).
- [ ] **Step 3: Implement** the availability rule from the Global Constraints and the card.
- [ ] **Step 4: Run** the tests and `test/controllers/api/v1/bundles_controller_test.rb` (iframe `no_onboarding` still skips the choice) — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "offer recipients to sign on paper when the author allows scans"`

### Task 6: Signer's paper signing page

**Files:**
- Create: `app/controllers/contracts/paper_signatures_controller.rb` (`show`, `submit`, `destroy`), `app/controllers/contracts/paper_signature_pages_controller.rb` (`create`, `update` (position), `destroy`, `show` (image bytes)), `app/controllers/concerns/paper_signer_resolution.rb` (finds the contract by UUID, the active recipient by `params[:recipient]` within the contract, its signer contract; 404 for unknown/withdrawn; redirects with `bundles.sign.signature_no_longer_required` when superseded; refuses `paper_signing_available_for?` false with a redirect to `signing_page_path`), views `app/views/contracts/paper_signatures/show.html.erb` (screens 2, 3, 4, 6 by state), `_steps.html.erb`, `_pages.html.erb`, `_submitted.html.erb`, `app/views/contracts/_paper_signature_state.html.erb`
- Modify: `config/routes.rb` (inside `resources :contracts`: `resource :paper_signature, only: [ :show, :destroy ], controller: "contracts/paper_signatures" do post :submit; resources :pages, only: [ :create, :show, :update, :destroy ], controller: "contracts/paper_signature_pages" end`), `app/policies/signing/signing_bundle_access_policy.rb` (`paper_sign?` = `web_context? && bound_recipient?`), `app/views/bundles/sign.html.erb:211-221` and `app/views/contracts/sign.html.erb:66-78` (render `_paper_signature_state` before the method choice: an open paper signature replaces the choice with screen-4 card + links „Pokračovať“/„Nahrať iný sken“ and „Zahodiť sken a podpísať inak“; the latest `returned` one without an open one shows the error alert above the choice), `app/controllers/contracts_controller.rb` `set_signer_contract` and `app/controllers/contracts/sessions_controller.rb:218-232` (redirect to `signing_page_path` with notice when the signer contract has a `submitted` paper signature), `config/initializers/filter_parameter_logging.rb` (`:reason`, `/\A(content|files?|blob|image|text|q)\z/`), `test/lib/request_log_filter_test.rb`, `docs/authorization.md` (new rows)
- Test: `test/integration/paper_signing_test.rb`

**Interfaces:**
- Consumes: Task 4 model API, Task 5 availability.
- Produces: routes `contract_paper_signature_path(contract, recipient:)`, `submit_contract_paper_signature_path`, `contract_paper_signature_pages_path`, `contract_paper_signature_page_path(contract, page, recipient:)`; partial `contracts/_paper_signature_state` with locals `(contract:, recipient:)`.
- Authorization: every action `authorize [ :signing, SigningBundleAccess.new(bundle: contract.bundle, recipient: recipient) ], :paper_sign?`; page/scan bytes via `send_data` with `disposition: "inline"`.

- [ ] **Step 1: Write the failing tests** (recipient without an account, as in `signature_request_flows_test.rb`; allow `scan` via `request_signature_from_web` with `allowed_methods: [ "qes", "scan" ]` — extend that helper with an `allowed_methods:` keyword)

```ruby
test "recipient uploads photos of the signed pages and submits them for review" do
  get contract_paper_signature_path(contract, recipient: recipient.uuid)
  assert_response :success
  assert_select "h1", "Podpis na papieri"
  post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ jpeg_upload ] }
  follow_redirect!
  assert_select "img[src*=?]", "/paper_signature/pages/"
  assert_includes response.body, "Dokument má 2 strany, nahrali ste 1"
  post submit_contract_paper_signature_path(contract, recipient: recipient.uuid)
  assert PaperSignature.sole.submitted?
  get sign_bundle_path(bundle, recipient: recipient.uuid)
  assert_includes response.body, "Sken sme odoslali na kontrolu"
  assert_select "input[value=paper]", count: 0
end

test "an unsupported file is refused and the draft stays" do
  post contract_paper_signature_pages_path(contract, recipient: recipient.uuid), params: { files: [ docx_upload ] }
  follow_redirect!
  assert_includes response.body, I18n.t("paper_signatures.errors.unsupported_file")
  assert PaperSignature.sole.draft?
end

test "a second visit reuses the draft"
test "discarding the scan brings back the method choice"
test "electronic signing is refused while a scan awaits review" # get signature_apps_contract_path → redirect with notice
test "another recipient cannot see or change the scan" # 404 for a recipient of another bundle
test "a returned scan shows its reason on the signing pages"
```

- [ ] **Step 2: Run** `bin/rails test test/integration/paper_signing_test.rb test/lib/request_log_filter_test.rb` — Expected: FAIL (no route).
- [ ] **Step 3: Implement** the controllers, concern, routes, policy query and views (layout per screens 2–4/6; server-rendered forms work without JS: a multiple file input, remove buttons, move up/down buttons, disabled submit without pages). Subscribe with `turbo_stream_from paper_signature`.
- [ ] **Step 4: Run** the test files and `test/controllers/contracts_controller_test.rb test/controllers/bundles_controller_test.rb` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "let recipients upload a scan or photos of the document signed on paper"`

### Task 7: Continue on a phone

**Files:**
- Create: `app/services/paper_signature_access_token.rb`, `app/helpers/qr_code_helper.rb`
- Modify: `app/controllers/concerns/paper_signer_resolution.rb` (accept `params[:token]` instead of `recipient`: the token resolves the paper signature and its recipient; it works only while that paper signature is a `draft` of this contract — adding/removing/moving pages and submitting; an expired token or any other state renders `contracts/paper_signatures/link_expired` with status 410, a token for another contract is 404), `app/views/contracts/paper_signatures/_steps.html.erb` (QR panel with the phone URL), phone layout of `show` (screen 5: below `lg` the steps collapse to the upload part when opened with a token), `app/policies/signing/signing_bundle_access_policy.rb` (token access authorizes `paper_sign?` for the token's recipient), `docs/authorization.md`
- Test: `test/services/paper_signature_access_token_test.rb`, `test/integration/paper_signing_test.rb`

**Interfaces:**
- Produces: `PaperSignatureAccessToken.generate(paper_signature, expires_at: 1.hour.from_now) -> String`, `PaperSignatureAccessToken.verify(token) -> PaperSignature | nil` (MessageVerifier, purpose `"paper-signature-access"`, payload `paper_signature_uuid` + `exp`, like `SessionAccessToken`).
- Produces: `qr_code_svg(url) -> ActiveSupport::SafeBuffer` (`RQRCode::QRCode.new(url).as_svg(module_size: 4, standalone: true, use_path: true)`).

- [ ] **Step 1: Write the failing tests**

```ruby
test "the phone link adds pages to the same draft without signing in" do
  token = PaperSignatureAccessToken.generate(draft)
  post contract_paper_signature_pages_path(contract, token: token), params: { files: [ jpeg_upload ] }
  assert_equal 1, draft.reload.pages.count
end

test "an expired phone link changes nothing" do
  token = PaperSignatureAccessToken.generate(draft, expires_at: 1.minute.ago)
  post contract_paper_signature_pages_path(contract, token: token), params: { files: [ jpeg_upload ] }
  assert_response :gone
  assert_equal 0, draft.reload.pages.count
end

test "a phone link of one contract does not open another" # token of draft A on contract B → 404
test "the phone link stops working after the scan is submitted" # → 410
test "the signing page shows a QR code with the phone link" # assert_select "svg" inside the QR panel and the token URL in a data attribute or <a>
```

- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "continue taking photos of signed pages on a phone through a QR code"`

### Task 8: Upload page behavior in the browser

**Files:**
- Create: `app/javascript/controllers/paper_pages_controller.js` (drag & drop and file picker → downsizes images to longest side 2400 px as JPEG quality 0.85 with a canvas, uploads with `fetch` + CSRF token, then lets the Turbo refresh show the tiles; PDFs upload unchanged; camera input `accept="image/*" capture="environment"` on the phone layout)
- Modify: `app/views/contracts/paper_signatures/_steps.html.erb`, `_pages.html.erb` (data attributes), `config/importmap.rb` only if needed
- Test: `test/system/paper_signing_test.rb` (runs with forgery protection on like `test/system/sdk_embedding_test.rb`)

**Interfaces:** Consumes Task 6 routes (`contract_paper_signature_pages_path`) and markup.

- [ ] **Step 1: Write the failing system test**

```ruby
test "recipient drops a photo, sees the page tile and submits" do
  visit contract_paper_signature_path(contract, recipient: recipient.uuid)
  attach_file "files[]", file_fixture("paper-page.jpg"), make_visible: true
  assert_selector "figure", text: "Strana 1"
  click_on "Odoslať na kontrolu"
  assert_text "Sken sme odoslali na kontrolu"
  assert PaperSignature.sole.submitted?
end

test "a large photo is downsized before upload" # attach test/fixtures/files/paper-page-large.jpg (about 4000×3000, committed); assert the stored page's blob byte_size is smaller than the fixture's
```

- [ ] **Step 2: Run** `bin/rails test:system TEST=test/system/paper_signing_test.rb` — Expected: FAIL.
- [ ] **Step 3: Implement** the Stimulus controller.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "downsize photos in the browser before uploading them"`

### Task 9: Review by the organization

**Files:**
- Create: `app/controllers/bundles/paper_signatures_controller.rb` (`show`, `approve`, `return_scan`, `scan`), views `app/views/bundles/paper_signatures/show.html.erb` (screen 9: header, info box, two side-by-side PDFs in `iframe`s — original `latest_source_content_version` and the scan from the `scan` action — and the decision bar; return dialog screen 10 as a native `<dialog>` opened by the „Vrátiť sken“ button, form with required `return_reason`)
- Modify: `config/routes.rb` (in the bundles block next to `resources :recipients`: `resources :paper_signatures, only: [ :show ], param: :uuid, controller: "bundles/paper_signatures" do member { post :approve; post :return_scan; get :scan } end`), `app/policies/bundle_policy.rb` (`review_paper_signatures?` → `manage?`), `app/models/contract.rb:359-361` (`awaiting_signature?` → `bundle&.awaiting_recipients?(contract: self) || (!signed_document_attached? && !paper_signatures.approved.exists?)`), `app/controllers/contracts_controller.rb:241-243` (`signed_document` falls back to the original document's file when none is signed), `app/helpers/recipients_helper.rb` (status `:awaiting_review` before `:pending`), `app/models/recipient.rb` (`awaiting_paper_review?`), `app/views/recipients/index.html.erb` (awaiting review: upload time and „Skontrolovať sken“ per submitted paper signature, prefixed with the file name when the bundle has several contracts; approved: „Podpis na papieri · schválil(a) …“ and „Stiahnuť sken“), `app/views/bundles/show.html.erb` (alert with „Skontrolovať sken“ while any scan awaits review), `app/views/shared/_signature_validation.html.erb` (local `paper_signatures`, default `@contract&.paper_signatures&.approved || []`; list them like visual stamps; suppress „no signatures“ when any), locales, `docs/authorization.md` (rows for the new actions)
- Test: `test/integration/paper_signing_test.rb`, `test/controllers/bundles/paper_signatures_controller_test.rb`

**Interfaces:**
- Consumes: `PaperSignature#approve!`, `#return!`, `PaperSignature::NoLongerReviewable`.
- Produces: `bundle_paper_signature_path(bundle, paper_signature)` (param `uuid`), `approve_…`, `return_scan_…`, `scan_bundle_paper_signature_path`; `Recipient#awaiting_paper_review? -> Boolean`.

- [ ] **Step 1: Write the failing tests**

```ruby
test "a member approves the scan and the bundle completes" do
  sign_in_with_tenant @owner, @organization
  get bundle_path(bundle)
  assert_includes response.body, "nahral(a) sken podpísaného dokumentu"
  get bundle_paper_signature_path(bundle, paper)
  assert_select "iframe", 2
  post approve_bundle_paper_signature_path(bundle, paper)
  assert bundle.reload.completed?
  assert recipient.reload.signed?
  get bundle_recipients_path(bundle)
  assert_includes response.body, "Podpis na papieri · schválil(a)"
end

test "a member returns the scan with a reason" do
  post return_scan_bundle_paper_signature_path(bundle, paper), params: { return_reason: "Chýba podpis na strane 2." }
  assert paper.reload.returned?
  assert recipient.reload.pending?
end

test "a mixed bundle completes with one electronic and one paper signature under the all rule"
test "with the any rule an approved scan supersedes the other recipient and cancels their draft"
test "approving after the recipient was withdrawn shows that the signature is no longer needed"
test "approving twice completes the signature once" # second post → notice, UsageRecord count stays 1
test "a member of another organization cannot open, approve or download the scan" # assert the Warden user and 403/redirect like Recipients
test "the scan downloads only for members" # anonymous get scan_… → denied
test "a contract signed only on paper is no longer awaiting and its download gives the original document"
test "the public signature validation lists the paper signature without the scan"
```

- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement**; denials follow `RecipientsController` (`rescue_from … render_tenant_record_denial`); `NoLongerReviewable` redirects to the bundle with `bundles.sign.signature_no_longer_required`.
- [ ] **Step 4: Run** `bin/rails test` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "let the organization approve or return scans of paper signatures"`

### Task 10: Emails

**Files:**
- Create: `app/jobs/notification/paper_signature_submitted_job.rb`, `paper_signature_reviewed_job.rb`; views `app/views/notification_mailer/paper_signature_submitted.{html,text}.erb`, `paper_signature_approved.{html,text}.erb`, `paper_signature_returned.{html,text}.erb`
- Modify: `app/mailers/notification_mailer.rb` (three methods), `app/models/paper_signature.rb` (`submit!` enqueues `Notification::PaperSignatureSubmittedJob`; `approve!`/`return!` enqueue `Notification::PaperSignatureReviewedJob`, all after commit), locales (`notification_mailer.paper_signature_*` subjects/bodies)
- Test: `test/mailers/notification_mailer_test.rb`, `test/integration/paper_signing_test.rb`

**Interfaces:**
- Produces: `NotificationMailer.with(user:).paper_signature_submitted(paper_signature)` (link `bundle_paper_signature_url`), `.with(recipient:).paper_signature_approved(paper_signature)`, `.with(recipient:).paper_signature_returned(paper_signature)` (reason, link `sign_bundle_url(bundle, recipient:)`).
- `PaperSignatureSubmittedJob#perform(paper_signature)`: every `tenant.notification_recipients(author: bundle.author)` regardless of `should_notify_author?` and webhooks. `PaperSignatureReviewedJob#perform(paper_signature)`: skips recipients without email.

- [ ] **Step 1: Write the failing tests**

```ruby
test "the organization is asked to review a submitted scan even with author notifications off" do
  perform_enqueued_jobs { submit_scan }
  mail = mails_to(@owner.email).sole
  assert_equal I18n.t("notification_mailer.paper_signature_submitted.subject"), mail.subject
  assert_match bundle_paper_signature_path(bundle, paper), link_in(mail, %r{/paper_signatures/})
end

test "the recipient learns why the scan was returned" do
  perform_enqueued_jobs { paper.return!(@owner, "Chýba podpis na strane 2.") }
  assert_includes mails_to("signer@example.com").sole.body.encoded, "Chýba podpis na strane 2."
end

test "the recipient learns the paper signature was approved"
```

- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement** following `RecipientNoLongerRequiredJob` and the existing templates.
- [ ] **Step 4: Run** — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "email the organization about scans to review and the signer about the result"`

### Task 11: API

**Files:**
- Create: `app/views/api/v1/contracts/_paper_signature.json.jbuilder`, action `scan` in `app/controllers/api/v1/paper_signatures_controller.rb` (or a member of contracts — keep `policy_scope([ :api, :v1, Contract ])` lookup and `authorize [ :api, :v1, contract ], :show?`)
- Modify: `app/views/api/v1/contracts/_contract.json.jbuilder` (`signed_document` only when attached and not awaiting; `null` when not awaiting and not attached; always `paper_signatures`: submitted and approved, ordered by `submitted_at`), `config/routes.rb` (`namespace :api … resources :contracts … resources :paper_signatures, only: [], param: :uuid do get :scan, on: :member end`), `public/openapi.yaml` (`PaperSignature` schema with `recipient`, `status` enum `submitted|approved`, `submitted_at`, `approved_at` nullable, `scan`; `ContractDetails.paper_signatures`; nullable `signed_document` description; scan endpoint; 404 of `signed_document` for paper-only), `docs/authorization.md`
- Test: `test/integration/api_signature_request_flows_test.rb`

**Interfaces:** Produces JSON shape exactly as in the spec's API section; `scan_api_v1_contract_paper_signature_url(contract, paper_signature)`.

- [ ] **Step 1: Write the failing tests**

```ruby
test "a bundle created through the API is signed on paper and the integrator downloads the scan" do
  bundle = create_bundle_via_api(contracts: [ pdf_contract_payload("a.pdf").merge(allowedMethods: [ "qes", "scan" ]) ], recipients: [ { email: "signer@example.com" } ])
  approve_paper_signature_of(bundle.recipients.sole)   # uses Task 4/9 helpers
  get api_v1_bundle_path(bundle), headers: api_headers
  contract_json = response.parsed_body["contracts"].sole
  assert_nil contract_json["signed_document"]
  paper = contract_json["paper_signatures"].sole
  assert_equal [ bundle.recipients.sole.uuid, "approved" ], paper.values_at("recipient", "status")
  get URI(paper["scan"]).path, headers: api_headers
  assert_equal "application/pdf", response.media_type
end

test "another organization cannot download the scan" # → 404
test "the contract status redirects once the paper signature is approved"
test "a submitted scan shows as submitted without approved_at"
```

- [ ] **Step 2: Run** — Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `bin/rails test test/integration/api_signature_request_flows_test.rb test/controllers/api` — Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "show paper signatures and their scans in the API"`

### Task 12: Documentation and full verification

**Files:**
- Modify: `CLAUDE.md` (Domain model: paper signatures and their review, availability rule, scan never a content version), `docs.index` texts in sk/en if the user guide describes signing methods (add „Podpis na papieri“ where allowed methods are listed) and retake affected screenshots with `bin/rails test test/user_guide/screenshots.rb`, `.env.sample` only if `scan` should be shown as an example

- [ ] **Step 1: Run** `bin/rails test && bin/rails test:system` — Expected: all PASS (report any pre-existing failure by name).
- [ ] **Step 2: Run** `bin/rubocop && bin/brakeman --no-pager && bin/rails zeitwerk:check` — Expected: no offenses, no warnings.
- [ ] **Step 3: Compare** sk/en flattened key sets (`ruby -ryaml -e '…'` as in CLAUDE.md) — Expected: identical apart from Slovak `few` plurals.
- [ ] **Step 4: Commit** `git commit -m "document paper signing"`
