# Autogram Portal (AGP)

Rails 8 app for eIDAS electronic signatures: upload, sign (Autogram, eIdentita, AVM, Podpisuj, AdES evidence), validate, request signatures from others, API for integrators, federation between portal instances. See README.md for the product overview and docs/federation.md for federation.

## Commands

```bash
bin/dev                          # web + tailwind watcher (Procfile.dev)
bin/rails test                   # whole Minitest suite (parallel)
bin/rails test test/integration/signature_request_flows_test.rb:42
bin/rubocop                      # must stay clean (rails-omakase style: `[ "a", "b" ]` with inner spaces)
bin/brakeman
bin/rails zeitwerk:check          # verify autoloading after adding/renaming classes
bin/rails test test/user_guide/screenshots.rb   # retake user guide screenshots (public/docs/screenshots/<locale>)
bin/rails db:migrate && bundle exec annotaterb models   # re-annotate models/fixtures/tests after schema changes
```

- Run the server for other devices with `bin/rails server -b 0.0.0.0`. `bin/dev` exits without a TTY because the tailwind watcher quits; run `bin/rails tailwindcss:watch[always]` separately in that case.
- Mail in development: `/letter_opener`. Jobs (GoodJob): `/admin/good_job`. In tests GoodJob runs jobs inline.
- `API_SKIP_AUTH=true` in `.env` skips API JWTs locally (uses `Tenant.second`).
- Staging (agp.dev.slovensko.digital, `config/deploy.staging.yml`) runs with `RAILS_ENV=staging`, so `Rails.env.production?` checks do not cover it.

## Domain model

- **Tenant** (UI name: "Organizácia") owns all data: `bundles`, `contracts`, `contract_validation_records`. Plans: `basic` (1 member) and `pro` (unlimited, `Tenant::MAX_MEMBERS`). Features on the tenant: `archivation`, `api`. Plan, features and name are changed only by admins (`Admin::TenantsController`).
- **Membership** joins users and tenants with role `owner` / `member`. All members see all tenant data; owners manage members and the API key. A tenant must keep an owner.
- **User** is only a person: login, recipients, signers, consents, identities. User features are only `admin` and `federation`. Users have no password (magic link via devise-passwordless or Google); `remember_token` backs "remember me".
  - Every user has a personal Basic tenant (`Tenant.create_personal_for!`, named after the email, not editable by the user), created with the user (also for users invited via `User.find_or_invite!`) and kept when they join organizations. Organization members therefore always pick a tenant after signing in; the UI recognizes it by the Basic plan: the selection page labels Basic tenants "Personal" and the sidebar shows "Personal organization" instead of the name.
- **Bundle** has one or more **Contracts**; a contract has one or more **Documents** (several documents = one ASiC-E container, XAdES/CAdES). Bundles and contracts are owned by the tenant, which is always the sender (`sender_display_name`); their optional `author` (the user who uploaded the contract / sent the bundle on the web) only routes author notifications and never grants access. A bundled contract always has its bundle's tenant (validated); a contract without a tenant is anonymous. The web UI creates a bundle from one uploaded document ("Poslať na podpis"); bundles with several contracts come only from the API.
- **Recipient** = invited signer of a bundle (linked to a `User` by email when one exists). Signing goes through `Signer` (STI: `RecipientSigner`, `UserSigner`, `AnonymousSigner`) → `SignerContract` (signed/declined/superseded) → `Session` (STI per signing app). Bundle `signing_rule`: `all`, `any`, `threshold`. Superseded or withdrawn recipients must not be able to sign.
- Recipients are emailed only by the explicit notify action (web "Odoslať e-mail"); adding a recipient, including via the API, sends nothing.
- Signing methods come from ENV `ALLOWED_METHODS` (default `qes,ades`), read once into `Contract::ALLOWED_METHODS` when the class loads, so tests cannot change them through ENV. `qes` implies `standalone_qes` (Podpisuj and other standalone apps), which recipients get only when the author allows it.
- Signatures made with the Autogram test certificate (CN "Autogram Test", validation result `INDETERMINATE`) count as valid only in development/test and on staging with `ALLOW_TEST_SIGNATURES=true` (`AutogramService#accepted_signature_result?`).
- When the tenant itself signs its bundle, an **author proxy** recipient is created (`Recipient.find_or_create_author_proxy_for!`); it is not a visible recipient.
- Author notifications go to the record's `author` while they are a member of the tenant, otherwise (API, older records, author left) to the tenant owners; never to the user who caused them, so an author signing their own document gets no email (`Tenant#notification_recipients`).
- Plan limits come from ENV through `PlanLimits` (blank = unlimited); `Tenant::Usage` checks them and records monthly usage (documents sent for signature, timestamps) in `UsageRecord`, which also is the PRO billing basis. Raise/rescue `PlanLimits::Exceeded`; retention runs in `TenantRetentionJob` and `AnonymousContractsCleanupJob`.

## Current tenant (web)

- `current_tenant` comes from `session[:current_tenant_id]` (`ApplicationController#resolve_current_tenant`). A user with exactly one tenant gets it automatically.
- A user with several tenants picks one after signing in: `ensure_tenant_selected` redirects signed-in users without a tenant to `TenantSelectionsController` (except Devise pages and embedded `iframe` signing actions, which skip it explicitly). The tenant cannot be switched without signing out.
- Authorization uses Pundit: collections via `policy_scope`, operations via `authorize`. Model ownership predicates are used by policies. Preserve other-own-tenant redirects through `render_tenant_record_denial` / `redirect_for_other_tenant`; `tenant_manages?` was removed.
- Consent with the current terms and privacy policy (`enforce_current_policy_consent`) is checked after tenant selection and skipped in PRO tenants, whose signed contract already covers it; Basic tenants and embedded signing before a tenant is chosen still require it.
- Organization settings live on the user settings page (`edit_user_registration_path(anchor: "organization")`, partial `tenants/_settings`).

## Authorization (Pundit)

- See `docs/authorization.md` for the action matrix, principals, denial responses and intentional exceptions. Policies are read-only; authenticate callers and validate tokens/assertions in the existing layers, and keep workflow/model invariants there.
- Principals are the `Web`, `TenantApi` and `Portal` types in `AuthorizationContext`. Anonymous web access requires a `Web` context with a nil user, not a nil principal or an API/portal context; a signed-in user without a selected tenant is a `Web` context with a nil tenant. Namespace lookup changes the policy, not the principal.
- Use namespace arrays, e.g. `authorize [ :api, :v1, @bundle ]`, `policy_scope([ :api, :v1, Bundle ])`, `authorize [ :signing, access ]`; avoid `policy_class:` / `policy_scope_class:` overrides. Policy names follow the record or bound subject class.
- Contract ownership (web and API) is `contract.tenant`; bundled contracts share the bundle tenant, so no bundle fallback is needed. Admin features do not bypass ordinary tenant ownership.
- `ApplicationController` verifies authorization after completed actions and scoping after `index`. Global index callbacks use an `action_name` predicate, not `only: :index`, because Rails validates missing callback actions. API bases inherit `ActionController::API` and retain separate verification hooks.
- Policies use the `ApplicationPolicy::Principal` helpers (`web?`, `signed_in?`, `in_tenant?`, `tenant_api?`, `portal?`) and the shared `TenantScope`s. Public/authentication actions (including UUID-public signing, documents and evidence) declare narrow `skip_authorization` exceptions instead of always-true predicates; public indexes also skip scoping. Admin and parent-authorized indexes use `skip_policy_scope` but still authorize their admin/parent gate. Retain additional scope verification for scoped non-index actions.
- `pundit_reset!` clears both caches and verification flags. Verify before resetting; Rails runs after callbacks in reverse registration order. Account deletion uses `prepend_after_action` for its reset.
- Preserve controller-specific denials (`rescue_from`); `rescue_responses` maps denials a controller leaves unhandled to 403 instead of 500. Compare `Pundit::NotAuthorizedError#query.to_s` (inferred queries can be strings, explicit queries symbols). Put authorization outside broad action rescue blocks so policy denials are not swallowed.
- Signing policies use bound `SigningBundleAccess` / `SigningSessionAccess` subjects. Session token-only access is limited to parameters/download/upload; deletion requires an allowed user. Keep token validation in `SessionAccessToken` and parent/session/signer binding intact.

## API

- `/api/v1/*`, RS256 JWT with `sub` = tenant id, verified by the tenant's `api_token_public_key`; the tenant needs the `api` feature (`app/lib/api_environment.rb`). Spec: `public/openapi.yaml` — update it with API changes.
- Federation API under `/api/federation/v1` uses portal-to-portal assertions, not tenant tokens.

## Embedding (SDK)

- Integrators embed bundle and contract signing pages with `/sdk.js` (`?iframe=`, example in `public/sdk-example.html`). Those actions call `allow_iframe`, which removes `X-Frame-Options` and adds `https:` to `frame-ancestors` (`AllowsCrossOriginFraming`); all other responses allow only the origins in `config/initializers/content_security_policy.rb`. Active Storage file responses allow cross-origin framing too (`config/initializers/active_storage.rb`), because embedded pages show PDFs in nested iframes.
- Embedded pages tell touch devices apart with Tailwind `pointer-coarse:`, not breakpoints: breakpoints measure the iframe, not the device, and headless Chrome in CI reports `pointer: none`.

## Conventions

- UI is Slovak by default; every user-facing string goes to both `config/locales/sk.yml` and `en.yml`, with identical keys (only Slovak `few` plural forms differ). After larger edits compare the flattened key sets: a mis-indented key shows "translation missing" in one language only. `:base` model errors live under `activerecord.errors.models.<model>.attributes.base.<key>`.
- The product name is "Autogram Portal" with a short "a", also when declined in Slovak ("Autogram Portalu", "v Autogram Portali"); the common noun "portál" keeps the long "á".
- Views: ERB + Tailwind + Stimulus/Alpine, importmap (no Node build). Tailwind v4 compiles only class names that appear literally in source files (views, helpers, locales); do not build them by interpolation such as `bg-#{color}-100` unless the full names exist elsewhere.
- The user guide (`/docs`, `app/views/docs`) takes its texts from `docs.index` in both locales; when a documented screen changes, update the texts and retake the screenshots (command above).
- External services are behind `AutogramEnvironment` (`autogram_service`, `avm_service`, `eidentita_service`, `ades_signing_service`); stub them there in tests.
- Keep model annotations (annotaterb) up to date in models, fixtures and model tests.
- Broadcast page refreshes with `broadcast_refresh_to`: it carries the request id, so the page that submitted the change ignores its own refresh. `broadcast_action_to(action: :refresh)` makes that page refresh itself and race its own redirect.

## Tests

- Minitest with fixtures (`test/fixtures`); `tenants(:one)`/`(:two)` are Basic tenants owned by `users(:one)`/`(:two)`.
- End-to-end signing flows: `test/integration/signature_request_flows_test.rb` (web) and `api_signature_request_flows_test.rb` (API). They use `test/support/signing_flow_helper.rb` (require it explicitly), which fakes Autogram validation for the whole test and signs through the real session/upload endpoints (`sign_with_autogram`). Add new signing scenarios there.
- Signing session pages print `Rails.application.config.action_controller.default_url_options[:host]`; tests rendering them must set it and restore it to `{}` rather than nil (the helper does).
- Integration tests sign in with `Devise::Test::IntegrationHelpers#sign_in`; for a user with several tenants, follow with `post tenant_selection_path(tenant_id: ...)`.
- Authorization request tests need confirmed users; assert the actual Warden actor when a denial could otherwise pass anonymously. Fixture emails are placeholders: replace them locally when email validations are exercised.
- List tests must include a matching nonempty record set and foreign-record exclusions. Empty results can hide invalid eager loads, such as the removed `Contract.user` association; `Membership.user` remains valid.
- Unsaved documents read their content from the upload's tempfile (`Document#content`), so build them from `Rack::Test::UploadedFile` / `ActionDispatch::Http::UploadedFile`; `{ io:, filename: }` attachments raise `ActiveStorage::FileNotFoundError` during validation.
- Use `bin/rails test` for the full suite; editor discovery may cover only a subset. System tests are separate (`bin/rails test:system`; CI runs both), and files under `test/` not ending in `_test.rb` (e.g. the user guide screenshots) run only when named explicitly. For ActiveJob enqueue assertions, use the test queue adapter locally instead of the default inline GoodJob adapter.
- Minitest 6 is bundled without `minitest/mock`, so `stub` is unavailable: switch `Rails.env=` or `ENV` inside an `ensure` block instead (see `test/services/autogram_service_test.rb`).
