# Paper signing ("Podpis na papieri") – design

Issue: #472. Screens: Figma file "Autogram Portal 2.0" (key `ibhM3spNhwjqFVv2GaOb9D`), page "Obrazovky", sections
"Podpis na papieri – návrh (podpisujúci)" (screens 1–6) and "Podpis na papieri – návrh (autor)" (screens 7–11).
The section "Podpisovanie skenom – súčasný stav" documents the legacy flow being removed. Every screen has a note
under it; the notes are part of this design.

## Intent

Some recipients cannot sign electronically. They should be able to print the document, sign it by hand and upload
a scan or phone photos back to the portal, and the sender should be able to rely on that signature. The portal
cannot verify a handwritten signature, so a member of the sending organization checks every scan and either
approves it (the recipient then counts as signed, like any other signature) or returns it with a reason (the
recipient uploads a new one).

The method exists today as a legacy "Fyzické podpisovanie" flow (ALLOWED_METHODS key `scan`) that never worked:
it only asks for the date the paper was posted, its form cannot even be saved (`PhysicalSession` misses
`signing_started_at`), signers without an account loop on the instructions, and nothing ever completes the
signature. It is replaced, not repaired.

## Goals

- A recipient of a bundle can sign a document on paper and upload a PDF scan or photos of the pages taken with a
  phone, also without an account.
- Photos are combined into one PDF. A signer on a computer can continue on a phone through a QR code.
- The sending organization reviews each scan side by side with the original and approves it or returns it with a
  reason. Only an approved scan counts as a signature.
- A paper signature counts towards the bundle's signing rule (all / any / threshold) exactly like an electronic one,
  with the same completion, notifications and usage records.
- The scan is evidence attached to that signer's signature (a counterpart, "rovnopis"); the document itself is not
  changed, so other recipients keep signing it electronically.
- Integrators can allow paper signing in bundles created through the API and get the paper signatures and their
  scans from the API.
- The legacy flow and `PhysicalSession` are deleted.

## Non-goals (this version)

- Paper signing in embedded (SDK iframe) signing, for federated recipients, for anonymous signers of public bundles
  or standalone contracts, and for the author signing their own bundle (author proxy). See "Availability".
- Verifying the handwritten signature automatically (OCR, comparison).
- Sending the paper original by post (the legacy wording) or tracking postal delivery. `PostalAddress` stays as it
  is (unused in the UI; out of scope).

## Anti-goals

- A scan must never become a content version of the contract or the "signed document"; it would replace electronic
  signatures and become the file later signers sign.
- A submitted scan must never count as a signature before a human approved it.
- Scans must not be reachable by public URLs (blob links); they may contain personal data and signatures.

## Constraints

- Rails 8, Minitest, Pundit with `verify_authorized` (see `docs/authorization.md`), ERB + Tailwind + Stimulus,
  importmap (no Node build). Slovak and English locales with identical keys. Model annotations (annotaterb).
- No PDF or image library is in the Gemfile today; `libvips` is in the Docker image, `image_processing` is
  commented out and Active Storage variants are disabled.
- License EUPL 1.2: new dependencies must be compatible.
- The signing pages are UUID-public (recipient UUID is the capability); test environment disables CSRF protection,
  so CSRF problems show only in system tests or production.

## Approaches considered

- **A. Extend the existing `PhysicalSession` (Session STI).** Reuses `Session#handle_status_change`, so approval =
  `signed!` and returning = `mark_failed!`. Least code, but ties the review workflow (draft pages, review, reasons,
  reviewer) to the signing-app session model and its broadcasts and iframe events.
- **B. A new standalone model (chosen).** Its own states for collecting pages, review and return, its own
  authorization and notifications. Cleaner separation from signing apps; the signature completion that today lives
  inside `Session` must be extracted so both paths share it.
- **C. Store the scan as a new content version of the contract.** Rejected: it would become the signed document and
  the source for later signers, and overwrite electronic signatures.

Chosen by the product owner: **B**, "to be cleaner"; `PhysicalSession` is deleted.

## Design

Decided with the product owner unless marked *(designer's call)*; those are open to change during review.

### Availability

Paper signing is offered to a signer only when all hold:
- the contract's `allowed_methods` include `scan` (the author enables it in the advanced settings before sending;
  off by default – screen 7) and `scan` is in ENV `ALLOWED_METHODS`;
- the signer is an active, non-federated recipient of a bundle (not the author proxy, not an anonymous signer);
- the page is not embedded (`params[:iframe]` blank) *(designer's call: the SDK has no event for "submitted for
  review" and embedded uploads would hit CSRF; revisit with the API follow-up)*;
- the contract is a single PDF document *(designer's call: printing needs a printable file; same constraint as
  visual signing)*.

The method keeps the key `scan` everywhere (ENV, `allowed_methods`, API); `Contract#signing_methods_for` offers it
under a new internal name (e.g. `paper`) instead of `physical`. Author-facing label "Podpis na papieri", description
as on screen 7.

### Signer flow (screens 1–6)

- Method choice: card "Podpis na papieri" with a printer icon (screen 1).
- One page instead of the legacy instructions + onboarding + form (screen 2), three steps:
  1. download the document for printing (button);
  2. sign it by hand;
  3. upload: a dropzone for a PDF from a scanner or photos (JPG/PNG; HEIC is converted to JPEG by mobile browsers),
     and next to it a QR code to continue on a phone.
  No onboarding step; works without an account. "Odoslať na kontrolu" is disabled until something is uploaded.
  The printed file is the original document (not a signed version). The draft paper signature is created when the
  page opens, so the QR code works before anything is uploaded.
- Uploaded photos appear as page thumbnails that can be removed, reordered and added to (screen 3). If the number of
  pages differs from the document's page count, a warning is shown; submitting is still allowed.
- On submit, photos are combined in order into one PDF; an uploaded PDF is used as is.
- After submitting: confirmation that the scan awaits review, thumbnails, and "Nahrať iný sken" while it is not yet
  reviewed (screen 4).
- Phone (screen 5): the QR code opens a page for this one paper signature without signing in. The camera button
  opens the camera directly; uploaded pages appear on the computer page without reloading (Turbo broadcast), and
  the phone can submit as well.
- Returned scan (screen 6): the page shows who returned it, when and why, and the signer uploads a new scan.

### Data model

New model `PaperSignature` (name is the builder's to refine), belonging to a `SignerContract`:
- states: `draft` (collecting pages), `submitted` (awaiting review), `approved`, `returned`, `canceled`;
- pages uploaded while in draft, kept in order; on submit, the combined PDF `scan` is stored and the page files are
  no longer needed;
- `submitted_at`, `reviewed_at`, `reviewed_by` (user; nullified when the user is deleted), `return_reason`;
- at most one non-final (draft or submitted) paper signature per signer contract; a new upload after a return is a
  new record, so returned attempts stay as history *(designer's call)*;
- `SignerContract has_many :paper_signatures, dependent: :destroy`, so retention and bundle/contract deletion remove
  them with their files.

Delete `PhysicalSession`; a migration deletes any `sessions` rows of type `PhysicalSession` first (none are
expected, the legacy form never saved one), otherwise STI loading would fail.

### Completing a paper signature

Today the completion runs inside `Session` (`handle_status_change` → `mark_signer_contract_signed` →
`Contract#record_signature_request_on_signing!`, then `Contract#notify_signed!`). Extract it into one place (e.g.
`SignerContract#complete_signature!`) used by both sessions and paper approval, so the signing rule, superseding of
other recipients, bundle completion, author notifications, webhooks, federation "signed" push, usage records and
Turbo refreshes behave identically. The reviewer must not get mail about their own approval (pass them as the user
to exclude).

Approval and return are allowed only while the paper signature is `submitted` and its signer contract is still
awaiting (not superseded, declined or withdrawn); otherwise the review page explains that the signature is no
longer needed.

### Interplay with existing state

- While a paper signature is `draft` or `submitted`, the recipient's signing page for that contract shows the paper
  signing state (screen 4) instead of the method choice; to sign another way they first discard the draft or
  submitted scan *(designer's call; the discard control is not drawn – a link next to "Nahrať iný sken")*. Electronic
  signing endpoints refuse a signer contract with a submitted scan.
- When a signer contract is superseded (threshold met), the recipient withdrawn, or the bundle declined by the
  recipient, its draft/submitted paper signatures become `canceled`.
- A contract whose recipients all signed, some or all of them on paper, counts as signed: `Contract#awaiting_signature?`
  must follow the recipients for bundled contracts with recipients instead of requiring an electronically signed
  content version. Where the app offers "the signed document" and the contract has no electronic signature, it
  offers the original document instead (today these links crash without a signed version), and the paper
  signatures list offers the scans.
- Bundle state badges, dashboards and "Prijaté na podpis" keep treating a submitted scan as not yet signed.

### Review (screens 7–11)

- Recipient card in the bundle detail: new status badge "Čaká na kontrolu skenu" (blue) with the upload time and a
  "Skontrolovať sken" button; an info box at the top of the bundle detail while at least one scan awaits review
  (screen 8).
- Review page: scan pages next to the original pages, page by page; an info box that the portal cannot verify the
  signature; a decision bar (sticky at the bottom) with "Vrátiť sken" and "Schváliť podpis" (screen 9).
- Returning requires a reason in a dialog (screen 10).
- Any member of the organization that owns the bundle may review (`BundlePolicy#manage?`), like other bundle
  actions.
- After approval the recipient is "Podpísané" with "Podpis na papieri · schválil(a) <name> <time>" and a
  "Stiahnuť sken" link for members (screen 11). The public signature validation box lists approved paper
  signatures with name and date and "overené odosielateľom", without the scan.

### Notifications

- Scan submitted → email to the organization's notification recipients (`Tenant#notification_recipients`: the
  author while a member, else owners) with a link to the review page. Sent even when the bundle's author
  notifications are off or it has a webhook, because it asks for an action *(designer's call)*.
- Approved → the usual signing notifications through the shared completion, plus an email to the signer that the
  signature was accepted *(designer's call)*.
- Returned → email to the signer with the reason and a link to the signing page, in the recipient's locale.
  Recipients without an email see it only on the signing page.

### Files, limits and privacy

- Accepted uploads: one PDF, or JPG/PNG photos. The browser downsizes photos before uploading (e.g. longest side
  ~2400 px, JPEG) so phone photos fit the limits *(designer's call)*; the server combines photos into a PDF with a
  pure-Ruby, EUPL-compatible library (Prawn suggested; HexaPDF is AGPL).
- The combined scan counts towards the document size limit (`PlanLimits.max_document_bytes`) and the tenant's
  storage usage (`Tenant::Usage#storage_bytes` must include scans). Like signed versions today, the tenant's storage
  limit does not stop a signer from submitting.
- Scans and page images are served only through authorized actions: to members of the owning organization, and to
  the signer through the recipient UUID capability (draft/own pages only). No public blob URLs.
- The phone link uses its own signed, expiring token bound to the paper signature (`SessionAccessToken` is bound to
  sessions and cannot be reused). It allows only adding/removing pages and submitting.
- Request logs must not contain uploaded files or the return reason (extend `filter_parameter_logging`).

### API (decided with the product owner)

- `allowedMethods: ["scan"]` stays accepted when creating bundles and contracts.
- Contract details (`GET /contracts/{id}`, and contracts inside `GET /bundles/{id}`) get a new array
  `paper_signatures`, one item per paper signature that is `submitted` or `approved` (returned and canceled attempts
  are left out):
  ```json
  "paper_signatures": [
    {
      "recipient": "<recipient uuid>",
      "status": "approved",
      "submitted_at": "2026-11-25T14:32:00Z",
      "approved_at": "2026-11-25T15:02:00Z",
      "scan": "https://…/api/v1/contracts/<id>/paper_signatures/<id>/scan"
    }
  ]
  ```
  (`status` is `submitted` or `approved`; `approved_at` is null while submitted.)
- `signed_document` stays the electronically signed file. In a mixed bundle it carries the electronic signatures
  only. For a contract signed only on paper it is `null`, and `GET /contracts/{id}/signed_document` answers 404.
  The JSON must not fail when there is no signed version (today `_contract.json.jbuilder` would).
- `scan` is an API endpoint authenticated with the tenant's JWT like the rest of the API, answering with the PDF; no
  public blob URL.
- Status endpoints and webhooks keep their meaning: when a contract or bundle completes thanks to paper signatures,
  `GET …/status` redirects to the details and `contract.signed` / `bundle.all_signed` fire as today.
- `public/openapi.yaml` documents `paper_signatures`, the scan endpoint, and the nullable `signed_document`.
- Embedded (SDK) signing still does not offer paper signing (see Availability).

### Removing the legacy flow

Delete `PhysicalSession`, `ContractsController#physical_signing/#create_physical_session` and their callbacks,
`contracts/physical_signing.html.erb`, the onboarding step `physical_instructions` (controller, view, routes,
`first_step`/`redirect_to_next_page` branches), the `physical` branch of `signing_method_controller.js` and of
`_signing_method_choice`, and their locale keys (sk/en). Update `docs/authorization.md` (remove the legacy actions,
add the new ones) and the stale `paper` value in the OpenAPI `SignatureMethod` enum.

## Left to the builder

- Names of the model, states, controllers, routes and locale keys; whether pages are a `has_many_attached` or a
  separate page model; how ordering is stored.
- How page counts are read (original and uploaded PDF), and the exact downsizing parameters.
- The PDF library, as long as it is pure Ruby and license-compatible.
- Token lifetime for the phone link (suggest about one hour) and how the computer page learns about new pages
  (Turbo stream on the paper signature).
- Email wording (sk/en) following the existing notification mailers.
- Where exactly the shared completion method lives, as long as sessions and paper approval both use it.
- Updating the user guide (`docs.index`) texts and screenshots if documented screens change (CLAUDE.md).

## Testing

- End-to-end scenarios in `test/integration/signature_request_flows_test.rb` with `SigningFlowHelper`:
  recipient without an account uploads photos → author approves → bundle completes; returned scan → new upload →
  approval; mixed bundle (one electronic, one paper) under "all" and "any" rules; superseded/withdrawn recipient's
  pending scan is canceled and cannot be approved.
- Authorization tests for the review actions (members of the owning tenant only, actual Warden actor asserted) and
  for the signer's and phone-token access.
- Model tests for states, combining photos into a PDF, size limits and storage counting.
- API scenarios in `test/integration/api_signature_request_flows_test.rb`: bundle created through the API with
  `scan`, recipient signs on paper, approval → `paper_signatures` with the scan downloadable with the JWT,
  `signed_document` null for a paper-only contract, `all_signed` webhook; another organization cannot download the
  scan.
- A system test for the upload page with forgery protection on (thumbnails, ordering, submit), and that paper
  signing is not offered in embedded signing.
