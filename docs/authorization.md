# Authorization and Pundit adoption

## Scope and status

The migration covers application authorization across web management, tenant API,
signing and federation. Existing permissions, responses and UI visibility must be
preserved. Delivery is incremental; installing Pundit does not migrate an endpoint.

Implemented application authorization:

- Pundit 2.5.2, a default-deny `ApplicationPolicy`, and explicit principal contexts.
- Organization updates, API-key editability, membership management and leaving.
- Tenant selection for signed-in users without a selected tenant.
- Admin controller access. The admin route and GoodJob guards remain unchanged.
- Organization view owner/API-key permissions and focused parity tests.
- Bundle, contract and recipient management; selected-tenant lists and dashboard.
- Person-scoped received bundles and federation invitations.
- Archivation records, signed-content history and private evidence downloads.
- Tenant API policies/scopes on the contract tenant (bundled contracts share the bundle tenant).
- Bound bundle/session signing subjects and explicit UUID-public permissions.
- Federation portal policies/scopes, public preview and authenticated broker claim.
- Self-account management, admin-only feature editing and permission-bearing views.

`ApplicationController` verifies authorization after every completed web action and
policy scoping after `index`. The index condition uses `action_name` rather than
`only: :index`, because Rails checks for missing callback actions even in controllers
without an index. Public/authentication actions explicitly call `skip_authorization`;
public indexes also call `skip_policy_scope`. These checks detect omissions, not
grant permissions. The separate API bases retain their own verification hooks.

Admin indexes and parent-authorized recipient/signature-field indexes explicitly
skip policy-scope verification; their admin or parent policy checks remain required.
Additional scope checks remain for received bundles, archivation mutations, API
record lookups and federation invitation withdrawal. Route guards and mounted
engines retain their own mechanisms. Superseded web ownership and session-access
guards were removed.

## Requirements

| ID | Requirement |
| --- | --- |
| AUTH-1 | Preserve permissions, denial responses, side effects and UI visibility. |
| AUTH-2 | Use the selected tenant, not all tenants a person belongs to. |
| AUTH-3 | Keep authentication, cryptographic verification and model invariants in their existing layers. |
| AUTH-4 | Deny unimplemented policy operations and test each migrated principal/operation. |
| AUTH-5 | Migrate all application authorization in separately verified slices. |

## Policy conventions

`AuthorizationContext::Web` holds the resolved user and selected tenant. Do not
substitute `User#default_tenant` or a request-supplied tenant. Ordinary tenant
policies do not grant administrators a global ownership bypass.

A signed-in user without a selected tenant is a `Web` context with a nil tenant.
`ensure_tenant_selected` redirects such users to tenant selection, except on
Devise pages and on embedded (`iframe`) signing actions, where recipients sign as
themselves. Tenant policies deny a nil tenant, so these users only reach
person-level permissions.

`AuthorizationContext::TenantApi` contains the tenant returned by the existing JWT
authenticator. API policies do not require a user or reimplement API-feature/token
verification. Development's existing `API_SKIP_AUTH` behavior is unchanged.
Document scopes reuse the contract scope so the ownership union has one definition.

`AuthorizationContext::Portal` contains the portal from the verified assertion.
Required assertion scopes, revocation and signature verification remain in
`PortalAssertionAuthenticator`; the assertion and claim JTI remain available to the
controller for grant issuance. A web or tenant-API context cannot impersonate a
portal principal.

`SigningBundleAccess` carries the resolved bundle and recipient after existing
grant/UUID/user/public/manager lookup. `SigningSessionAccess` carries the contract,
parent-bound session, resolved signer contract and a token-validity fact computed
by `SessionAccessToken`. Neither subject stores raw tokens. Session token access
is evaluated only for parameters/download/upload; destruction checks user access,
and AdES mutations additionally require the resolved signer/session to match.
Session permissions require a nonempty contract; missing parents do not establish
a valid binding.

Policies are read-only: they do not create records, send mail, issue grants or
change signing state. Reuse domain predicates. Capacity, last-owner protections
and workflow guards stay in models/services so other callers retain them.

The base policy denies CRUD operations; the base scope raises until implemented.
Anonymous web requests use `AuthorizationContext::Web` with a nil user. A nil
principal or a context from another interface does not grant public web access.

Use Pundit's namespace arrays instead of explicit policy-class overrides:

```ruby
authorize [ :api, :v1, @bundle ]
policy_scope([ :api, :v1, Bundle ])
authorize [ :api, :federation, :v1, @recipient ]
policy_scope([ :received, Bundle ])
authorize [ :signing, access ]
authorize [ :tenant_selection, tenant ]
```

Policies follow the record's class name within the namespace. Federation requests
therefore use `Api::Federation::V1::RecipientPolicy`; signing subjects use
`Signing::SigningBundleAccessPolicy` and `Signing::SigningSessionAccessPolicy`.
Tenant selection uses `TenantSelection::TenantPolicy`, with
`[ :tenant_selection, :tenant ]` for its headless show/create operations.
Namespace lookup selects a policy, not a principal or tenant. Keep policy scopes
for collection isolation and authorize individual operations separately.

Migrated controllers call `authorize` before protected mutations and inherit
`verify_authorized` from their base. Membership management authorizes the parent tenant;
the existing `@tenant.memberships.find` enforces the child relationship. A separate
membership policy is unnecessary while all operations have this same parent gate.

Denial presentation remains controller-specific. Tenant-owner denials retain the
organization-settings redirect and translated alert; admin denials retain 403.
Do not introduce a generic global 403 handler that changes existing responses.
Normalize `Pundit::NotAuthorizedError#query` before comparing query names: inferred
controller queries are strings, while explicit queries may be symbols.

Organization views use the same owner/API-key predicates as the backend. Existing
display-only restrictions remain separate: the view hides self-removal and limits
the leave button, while endpoints allow attempts subject to model safeguards.
Do not strengthen endpoint permissions merely to match button visibility.

Pundit caches policies within a request. Reset it when the principal changes.
`pundit_reset!` also clears verification flags: account deletion uses
`prepend_after_action` for its reset. Rails runs after callbacks in reverse
registration order, so inherited verification executes first, then reset.
Authentication redirects that halt before an action do not require a policy call.

## Migrated action matrix

| Controller/action | Principal and lookup | Permission | Existing denial or invariant |
| --- | --- | --- | --- |
| `Tenants#update` | Web, `current_tenant` | `TenantPolicy#update?`: selected-tenant owner | Settings redirect, `tenants.alerts.owner_required` |
| `Tenants#update` attributes | Same | `permitted_attributes_for_update`: API public key only when API enabled | API-disabled owner update still succeeds as a no-op; name/plan/features remain ignored |
| `Tenants#leave` | Web, current tenant membership | `TenantPolicy#leave?`: selected-tenant member | Last owner gets the model error and remains signed in; success signs out |
| `Tenants::Memberships#create` | Web, current tenant | `TenantPolicy#manage_memberships?`: owner | Owner redirect precedes inviting; capacity/role checks stay in models |
| `Tenants::Memberships#destroy` | Web, child found through current tenant | Same parent policy | Non-owner redirect precedes child lookup; foreign child 404; last-owner model error preserved |
| `TenantSelections#show` | Signed-in user without selected tenant | `TenantSelection::TenantPolicy#show?` | Signed-out users redirect to login; a selected tenant redirects to the dashboard before authorization |
| `TenantSelections#update` | Same, `current_user.tenants.find` | `TenantSelection::TenantPolicy#update?`: membership | Foreign tenant 404; existing selection cannot be switched until sign-out |
| `TenantSelections#create` | Same | `TenantSelection::TenantPolicy#create?`: no existing tenant | Users with tenants get 404 without mutation |
| `Admin::Tenants#index/new/create/edit/update/add_member` | Web user, existing admin lookups | `AdminPolicy#access?`: admin feature | Controller 403 and existing route authentication preserved |
| `Admin::PortalInstances#index/new/create/edit/update/verify/revoke` | Same | Same headless admin policy | Same; portal/service validation remains unchanged |

The settings view's `manage_memberships?` and `edit_api_key?` predicates are checked
in integration tests. They are not a replacement for controller authorization.

| Controller/action | Principal and lookup | Permission | Existing denial or invariant |
| --- | --- | --- | --- |
| `Bundles#index` | Web, `BundlePolicy::Scope` | Selected tenant; `index?` | Existing awaiting/completed/declined/no-recipient filters preserved |
| `Bundles#show/edit/update/destroy` | Web, global UUID lookup | `BundlePolicy` management queries | Unrelated record 404; another own tenant redirects with guidance, without switching |
| `Recipients#index/create/notify/destroy` | Web, global bundle UUID and parent-scoped recipient UUID | `BundlePolicy#manage_recipients?` | Same management denials; notifiable/removable state and validation errors remain separate |
| `Bundles#received` | Web user, received bundle/invitation scopes | `Received::BundlePolicy#index?` | Person-scoped across selected tenants; state/active/visible filters retained |
| `Dashboard#index` | Web, multiple policy scopes | `DashboardPolicy#index?` | Sent data uses selected tenant; received counts use person; archivation feature controls archive scope |
| `Contracts#index` | Web, direct-tenant scope, then `standalone` | `ContractPolicy#index?` | Original direct association and state/order filters |
| `Contracts#new/create` | Web, including anonymous | `ContractPolicy#new?/create?` | Anonymous policy agreement and upload validation unchanged; authorization before payload effects |
| `Contracts#show/update/destroy` | Web, global UUID; anonymous claim before management authorization | Anonymous or selected-tenant management | Foreign edit redirect; another own tenant gets guidance; bundled-delete/state checks retained |
| `Contracts#signature_parameters/update` request-signature branch | Web, existing contract | `request_signatures?`: selected-tenant management | 403 for anonymous/non-manager; ordinary signing branch remains UUID-accessible |
| `Contracts#signature_extension/extend_signatures` | Web, global UUID | Selected-tenant management | 403; extension eligibility and service errors retain their own responses |
| `Contracts#content_versions` | Web, global UUID | Management AND contract-tenant archivation | 403 |
| `Contracts::SignatureFieldPreparations#index/edit/create/update/destroy/finalize` | Web, contract UUID and parent-scoped preparation ID | `prepare_signature_fields?`: bundle management | Foreign 403, another own bundle tenant guidance, ineligible format/state 422 |
| `ContractValidationRecords#index/destroy/refresh` | Web, feature gate and selected-tenant policy scope | Archivation and record tenant | Disabled-feature root redirect; foreign ID 404; refreshability remains workflow rule |
| `Contracts#show_bundle/actions/sign/signature_apps/physical_signing/create_physical_session/visual_signing/create_visual_session/signed_document/validate` | Web, UUID lookup; existing recipient/preparation resolution | Explicit `public_access?` | Existing UUID accessibility, onboarding, signer, appearance and state constraints preserved |
| `Contracts#authenticate_for_actions` | Web, UUID lookup | Signed-in user OR anonymous contract | Existing-user redirect, anonymous pending-claim flow, otherwise 403 |
| `Contracts::Onboarding#show/update` | Web, UUID and parent-bound active recipient | Contract `public_access?` | Invalid/withdrawn recipient, onboarding state and cookies retain existing behavior |
| `Bundles#sign/autogram_batch` | Web, bound signing subject | Recipient capability OR public bundle OR selected-tenant manager | Lookup precedence unchanged; invalid grant/mismatch 404, withdrawn signing 410, batch eligibility stays separate |
| `Bundles#accept/decline` | Web, recipient found through bundle | Bound recipient capability | Existing UUID/user lookup retained; withdrawal/completion/superseding responses unchanged |
| `Contracts::Sessions#create/show` | Web, bound signing subject | Existing signer resolution / nested session | Creation/preparation/completion redirects unchanged; UUID/session display is not hardened |
| `Contracts::Sessions#parameters/download/upload` | Web, contract UUID and nested session ID | Valid bound token OR allowed user | 403; expiry/withdrawal checked by token service; format/attachment/upload errors unchanged |
| `Contracts::Sessions#destroy` | Same | Allowed user only, never token alone | 403; managers and existing signer ownership/email semantics retained |
| `Contracts::Sessions#request_verification/verify_verification/complete_signing` | Same, resolved signer contract | Session matches resolved signer | 403 on mismatch; AdES type and service errors remain separate |
| `Contracts::Sessions#get_webhook/standard_webhook` | Web anonymous context, nested session | Explicit bound-session queries | No new user authentication; AVM type/protocol checks and CSRF exceptions preserved |
| `Documents#visualize/pdf_preview/download` | Web, global document UUID | Explicit public operation queries | Numeric IDs 404; owned documents remain UUID-accessible anonymously; visualization errors unchanged |
| `SignatureEvidenceVerifications#show/download` | Web, public reference | Explicit public access | Missing reference/detail/download outcomes and manifest fallback unchanged |
| `SignatureEvidenceVerifications#download_private` | Web, public reference | Existing private-evidence predicate | Missing record/attachment 404; denied access 403; absent-record branch explicitly skips authorization |
| `Api::V1::Contracts#create/show/status/signed_document/destroy` | TenantApi; API contract scope for existing records | Contract tenant | Existing `Contract not found`, CRUD bodies, polling headers and redirects |
| `Api::V1::Documents#show` | TenantApi, API document scope | Parent contract tenant | Existing `Document not found`; orphan documents excluded |
| `Api::V1::Bundles#create/show/status/destroy` | TenantApi, tenant bundle scope | Bundle tenant, not public visibility | Existing `Bundle not found`, duplicate UUID conflict, bodies and polling headers |
| `Api::V1::Hello#show/show_auth` | Public / TenantApi | Explicit public skip / API hello policy | Existing public message and authenticated tenant message |
| `Api::Federation::V1::Requests#show/claim` | Verified Portal and recipient UUID | Federated recipient assigned to caller | Portal mismatch 403, state 409, claimant mismatch 422, bundle mismatch 404; grants unchanged |
| `Api::Federation::V1::RequestInvitations#create/withdraw` | Portal, caller-bound lookup/scope | Caller portal ownership | Foreign invitation 404; payload/status behavior unchanged |
| `Federation::Requests#show/claim` | Web public / authenticated user | Preview / claim policy | Existing broker URL checks, remote errors and signing continuation |
| `Users::Registrations#edit/update/destroy` | Authenticated Devise self resource | `UserPolicy#manage_account?`; `edit_features?` for admin | Non-admin features ignored, admin flag retained; confirmation phrase and model deletion errors unchanged |

Contract deletion remains behind the existing authenticated route even though the
controller policy permits anonymous-contract management. Display-only rules also
remain distinct: preparation/extension format and plan checks, decline/accept
button state, federation navigation feature and archive controls do not silently
strengthen endpoint permissions.

## Completed migration sequence

| Task | Depends on | Scope and acceptance |
| --- | --- | --- |
| P01 | None | Foundation and tenant/admin slice above; AUTH-1 through AUTH-4. Implemented. |
| P02 | P01 | Implemented managed web policies, private evidence and tenant/person scopes with parity tests. |
| P03 | P01 | Implemented tenant API contexts/policies/scopes, ownership union and wire-response regression tests. |
| P04 | P02 | Implemented operation-specific session and bundle policies, public-resource queries and bound subjects. |
| P05 | P01 | Implemented portal policies/scopes and web broker permissions; assertion/claimant/grant rules preserved. |
| P06 | P02-P05 | Audited controller/view decisions and route boundaries; inherited verification, explicit exceptions and omission-detection tests implemented. |

For a new endpoint, first classify its principal, lookup/binding constraints,
permission, denial response and workflow guards. Add a policy/query or explicit
documented public/authentication classification, authorize before protected effects,
and retain the inherited verification defaults. Declare narrow explicit skips for
public/authentication actions or parent-authorized collections. Add scope verification
for scoped non-index actions. Collections need every relevant policy scope, not just
a headless authorization call. Add behavior-level denial/isolation
tests; verification hooks alone cannot prove the correct policy or scope was used.

### Retained boundaries

| Surface | Preserve during migration |
| --- | --- |
| Bundles management and recipients | Policy management, OtherTenantRecord presentation, parent-scoped recipient lookup |
| Bundle received and dashboard | Person-scoped invitations/received requests; selected-tenant sent records; existing state/count filters |
| Contracts CRUD/actions | Contract tenant ownership, anonymous permissions, anonymous-claim ordering, per-action denial responses |
| Contract validation history/records and evidence-private download | Selected tenant and archivation feature; refreshability and attachment errors remain distinct |
| Contract signing, onboarding and visual/physical signing | Existing user/recipient/anonymous resolution, withdrawal/superseding responses and preparation guards |
| Session parameters/download/upload | Bound, valid session token OR existing allowed-user checks; expiry and withdrawal remain validated by SessionAccessToken |
| Session destroy | Allowed-user branch only; session token alone never grants deletion |
| Session create/show/verification/completion | Parent/session/signer matching and existing method/state/preparation checks, not one generic signing permission |
| Session AVM webhooks | Existing protocol/service checks and CSRF exception, not newly invented user authentication |
| Bundle sign/batch/accept/decline | Existing grant/UUID/user/public/manager resolution precedence; each action retains its own rules |
| Documents preview/download and contract validation/signed download | Existing UUID-accessible behavior; no new blanket tenant scope |
| Evidence public lookup/download | Public reference access; distinct private-package permission |
| Tenant API contracts/documents | Contract tenant scope, shared by document scopes |
| Tenant API bundles and hello | Tenant-owned CRUD/status, API-feature token authentication; hello remains public |
| Federation API requests | Assigned portal binding (403), claimability (409), claimant validation (422), show bundle mismatch (404) |
| Federation API invitations | Caller-portal-scoped creation/withdrawal; existing assertion scopes and payload responses |
| Federation web | Preview public, claim authenticated; broker/remote errors and ordinary signing continuation |
| Devise, consent, OAuth consent, tenant selection | Authentication/session/consent constraints remain in place; users without a selected tenant hold no tenant permissions |
| Root/about/docs/SDK/locale/ALTCHA/metadata/devtools/health/PWA | Intentional public or authentication-dependent utility behavior, not tenant resource access |
| GoodJob/LetterOpener/ActiveStorage | Existing engine/environment/token controls; app-controller policy hooks do not secure mounted engines or issued blob URLs |

The API bases inherit `ActionController::API`, not `ApplicationController`; both
include Pundit and provide their own verified principal.
Keep tenant-token and portal policies distinct from user-role policies.

Some actions broadly rescue exceptions. Put policy denials outside those blocks
or re-raise them explicitly; otherwise a denial may become an upload/visualization
or business error. Verification hooks check that a call occurred, not that the
right records were authorized or all collections were scoped.

Existing public/UUID-accessible rules are compatibility requirements, not a claim
that their security is sufficient. Record any hardening proposals separately.
No API contract, schema or role data migration is intended.

Devise sign-up/login/magic-link/confirmation/unlock/OAuth callbacks and policy/OAuth
consent remain authentication flows, not tenant-resource policy operations. Their
controllers declare action-specific verification skips; account edit/update/destroy
still require authorization. The magic-link route uses `Users::MagicLinksController`
solely to declare its skip, preserving Devise's token handling and existing URL.
Pending OAuth identity data stays session-bound. Web utility endpoints declare their
skips explicitly. SDK, metadata, health, PWA and mounted engines do not inherit the
web base and retain their existing controls. Existing route declarations for absent
contract edit/visualize actions are not new supported endpoints.

## Verification

Use Minitest and existing fixtures. Focused policy tests live in `test/policies`.
Controller tests assert actual statuses, redirects, alerts, record changes and
view visibility, including API-disabled owner updates and denied membership changes.

```sh
bin/rails test test/policies test/controllers test/integration
bin/rails test
bin/rubocop
bin/brakeman
bin/rails zeitwerk:check
```

Include existing signing/API/federation flow tests and scope
exclusion tests. Cover nil principal/tenant, wrong selected tenant, revoked
membership, nonmember admin, token mismatch/expiry, and cross-parent identifiers.
Preserve status, body, flash, headers and absence of unauthorized side effects.

### Initial slice checkpoint

Verified on 2026-10-01:

- Full Rails suite: 360 tests, 1,883 assertions, no failures/errors/skips.
- RuboCop: 305 files, no offenses.
- Brakeman: no errors or security warnings.
- Zeitwerk: application eager loading passed (existing mailer previews are excluded).
- Lockfile: only Pundit was added; existing dependencies were not upgraded.

The editor test runner discovers only a subset of this suite; use `bin/rails test`
for the final repository gate. No manual browser parity check has been performed.

### Complete migration checkpoint

Verified on 2026-10-01 after P02-P06:

- Full Rails suite: 422 tests, 2,197 assertions, no failures/errors/skips.
- RuboCop: 332 files, no offenses.
- Brakeman: no errors or security warnings.
- Zeitwerk: application eager loading passed; existing mailer previews remain excluded.
- Editor diagnostics and `git diff --check`: clean.
- Focused tests were run after each implementation slice, and a full checkpoint
	also passed after web management before API/signing/federation migration.

Request tests cover revoked membership, wrong selected tenant, nested identifiers,
authenticated private evidence isolation, API ownership union, federation response
codes and assertion scopes. Policy tests cover principal separation, session token
limits and signer binding. Bundle tests prove verification hooks detect omitted
authorization and scoping. Existing web/API signing and authentication flows pass.

No schema, role-data, public route URL, locale message or OpenAPI wire-format change was made.
Manual browser parity remains unverified; automated request/view assertions cover
the affected controls and responses.

### Inherited verification checkpoint

Verified on 2026-10-01 after enabling web defaults and explicit exceptions:

- Full Rails suite: 441 tests, 2,313 assertions, no failures/errors/skips.
- RuboCop: 334 files, no offenses; Brakeman: no errors or security warnings.
- Zeitwerk, editor diagnostics and `git diff --check`: clean.
- Regression tests cover inherited omission checks, public exceptions, protected
	account updates, real magic-link authentication and multi-tenant sign-in/reset ordering.
