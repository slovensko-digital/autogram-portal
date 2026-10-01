# Autogram Portal (AGP)

Rails 8 app for eIDAS electronic signatures: upload, sign (Autogram, eIdentita, AVM, Podpisuj, AdES evidence), validate, request signatures from others, API for integrators, federation between portal instances. See README.md for the product overview and docs/federation.md for federation.

## Commands

```bash
bin/dev                          # web + tailwind watcher (Procfile.dev)
bin/rails test                   # whole Minitest suite (parallel)
bin/rails test test/integration/signature_request_flows_test.rb:42
bin/rubocop                      # must stay clean (rails-omakase style: `[ "a", "b" ]` with inner spaces)
bin/brakeman
bin/rails db:migrate && bundle exec annotaterb models   # re-annotate models/fixtures/tests after schema changes
```

- Run the server for other devices with `bin/rails server -b 0.0.0.0`. `bin/dev` exits without a TTY because the tailwind watcher quits; run `bin/rails tailwindcss:watch[always]` separately in that case.
- Mail in development: `/letter_opener`. Jobs (GoodJob): `/admin/good_job`. In tests GoodJob runs jobs inline.
- `API_SKIP_AUTH=true` in `.env` skips API JWTs locally (uses `Tenant.second`).

## Domain model

- **Tenant** (UI name: "Organizácia") owns all data: `bundles`, `contracts`, `contract_validation_records`. Plans: `basic` (1 member) and `pro` (unlimited, `Tenant::MAX_MEMBERS`). Features on the tenant: `archivation`, `api`. Plan, features and name are changed only by admins (`Admin::TenantsController`).
- **Membership** joins users and tenants with role `owner` / `member`. All members see all tenant data; owners manage members and the API key. A tenant must keep an owner.
- **User** is only a person: login, recipients, signers, consents, identities. User features are only `admin` and `federation`. Users have no password (magic link via devise-passwordless or Google); `remember_token` backs "remember me".
  - Self-registration creates a personal Basic tenant. Users invited to an organization or created by an admin (`User.find_or_invite!`) do not get one. Joining an organization deletes an unused personal Basic tenant (`Tenant#add_member!`).
- **Bundle** has one or more **Contracts**; a contract has one or more **Documents** (several documents = one ASiC-E container, XAdES/CAdES). Bundles and contracts have no user; the sender is always the tenant (`sender_display_name`). A contract without tenant and bundle is anonymous.
- **Recipient** = invited signer of a bundle (linked to a `User` by email when one exists). Signing goes through `Signer` (STI: `RecipientSigner`, `UserSigner`, `AnonymousSigner`) → `SignerContract` (signed/declined/superseded) → `Session` (STI per signing app). Bundle `signing_rule`: `all`, `any`, `threshold`. Superseded or withdrawn recipients must not be able to sign.
- When the tenant itself signs its bundle, an **author proxy** recipient is created (`Recipient.find_or_create_author_proxy_for!`); it is not a visible recipient.
- Author notifications go to the tenant owners except the user who caused them (`author_notification_recipients`).

## Current tenant (web)

- `current_tenant` comes from `session[:current_tenant_id]` (`ApplicationController#resolve_current_tenant`). A user with exactly one tenant gets it automatically.
- A user with several tenants is **not signed in** until they pick one: `ensure_tenant_selected` signs them out, stores a pending user in the session (15 min) and `TenantSelectionsController` completes sign-in. The tenant cannot be switched without signing out.
- Authorization: list from `current_tenant.<association>`; for a single record use `record.managed_by?(current_tenant)` or `tenant_manages?(record)`, which raises `OtherTenantRecord` (redirect with an alert) when the record belongs to another tenant of the same user.
- Organization settings live on the user settings page (`edit_user_registration_path(anchor: "organization")`, partial `tenants/_settings`).

## API

- `/api/v1/*`, RS256 JWT with `sub` = tenant id, verified by the tenant's `api_token_public_key`; the tenant needs the `api` feature (`app/lib/api_environment.rb`). Spec: `public/openapi.yaml` — update it with API changes.
- Federation API under `/api/federation/v1` uses portal-to-portal assertions, not tenant tokens.

## Conventions

- UI is Slovak by default; every user-facing string goes to both `config/locales/sk.yml` and `en.yml`. `:base` model errors live under `activerecord.errors.models.<model>.attributes.base.<key>`.
- Views: ERB + Tailwind + Stimulus/Alpine, importmap (no Node build).
- External services are behind `AutogramEnvironment` (`autogram_service`, `avm_service`, `eidentita_service`, `ades_signing_service`); stub them there in tests.
- Keep model annotations (annotaterb) up to date in models, fixtures and model tests.

## Tests

- Minitest with fixtures (`test/fixtures`); `tenants(:one)`/`(:two)` are Basic tenants owned by `users(:one)`/`(:two)`.
- End-to-end signing flows: `test/integration/signature_request_flows_test.rb` (web) and `api_signature_request_flows_test.rb` (API). They use `test/support/signing_flow_helper.rb` (require it explicitly), which fakes Autogram validation for the whole test and signs through the real session/upload endpoints (`sign_with_autogram`). Add new signing scenarios there.
- Signing session pages print `Rails.application.config.action_controller.default_url_options[:host]`; tests rendering them must set it (the helper does).
- Integration tests sign in with `Devise::Test::IntegrationHelpers#sign_in`; for a user with several tenants, follow with `post tenant_selection_path(tenant_id: ...)`.
