# Autogram Portal

Web application for managing digital signatures.

Other electronic document signing platforms often lack support for advanced or qualified electronic signatures available under the EU's eIDAS standard, relying instead on simpler signatures without stronger legal validity. Our eIDAS-compatible signing portal addresses this gap by providing an open-source user-friendly platform for creating qualified electronic signatures using government-issued eID cards and other qualified signature creation devices.

Unlike existing alternatives, our project will integrate seamlessly with desktop and mobile signer applications, both open-source and commercial, enabling intuitive qualified document signing, validation, archiving, and API integration with third-party systems. Instances are planned to behave federatively and exchange documents simplifying the adoption of qualified electronic signatures across Europe, reducing reliance on proprietary solutions, and improving digital administrative workflows.


**Demo:** [agp.dev.slovensko.digital](https://agp.dev.slovensko.digital)

## Funding

This project is funded through [NGI Zero Core](https://nlnet.nl/core), a fund established by [NLnet](https://nlnet.nl) with financial support from the European Commission's [Next Generation Internet](https://ngi.eu) program. Learn more at the [NLnet project page](https://nlnet.nl/project/eIDAS-portal).

[<img src="https://nlnet.nl/logo/banner.png" alt="NLnet foundation logo" width="20%" />](https://nlnet.nl)
[<img src="https://nlnet.nl/image/logos/NGI0_tag.svg" alt="NGI Zero Logo" width="20%" />](https://nlnet.nl/core)

## What It Does

Autogram Portal provides comprehensive electronic signature management for individuals, organizations, and integrators:

### For Unregistered Users
- **Sign Documents** - Upload and sign documents using Autogram Desktop or Mobile
- **Verify Signatures** - Validate existing electronic signatures
- **View Document Contents** - Visualize ASiC-E containers and Slovak XML Datacontainers (special XML format for eGovernment)
- **Share for Signing** - Generate shareable URLs for others to sign your documents

### For Registered Users
Sign in via **Google OAuth2** or **email magic link** to access:
- **Manage Contracts** - Store and organize contracts in your profile
- **Track Signature Status** - Monitor pending and completed signatures
- **Extend Signatures** - Add timestamps to existing signatures for long-term validity
- **Email Notifications** *(coming soon)* - Send contracts for signature via email

### For Integrators (API)
- **Create Bundles** - Programmatically create bundles of contracts via API
- **Embed Signing** - Integrate signing UI into your app using JavaScript SDK
- **Webhook Notifications** - Receive real-time updates when documents are signed
- **Manage Documents** - Upload, track, download, and delete signed documents


## Tech Stack

- Ruby on Rails 8
- PostgreSQL

## Quick Start

```bash
# Setup
cp .env.sample .env
bundle install
bin/rails db:setup

# Run
bin/dev
```

Visit `http://localhost:3000`

### GoodJob

We are using GoodJob for job queue. Dashboard is available at [/admin/good_job](http://localhost:3000/admin/good_job) for authenticated admin users.

## Configuration

Edit `.env` file:
- `API_SKIP_AUTH=true` - Skip auth in development
- `AUTOGRAM_SERVICE_URL` - Autogram service URL
- `AVM_URL` - Autogram AVM service URL
- `WEBHOOK_REQUIRE_HTTPS=true` - Require HTTPS for webhook destinations (defaults to true in production)
- `WEBHOOK_ALLOWED_HOSTS=host1,host2` - Optional allowlist override for internal webhook destinations
- `WEBHOOK_OPEN_TIMEOUT=3` - Outbound webhook TCP connect timeout in seconds
- `WEBHOOK_TIMEOUT=5` - Outbound webhook request timeout in seconds

## Development

```bash
# Tests
bin/rails test

# Code quality
bin/rubocop
bin/brakeman
```

## Deployment

We are using kamal for deployment.

Main branch is automatically deployed to staging at [agp.dev.slovensko.digital](https://agp.dev.slovensko.digital/)


## License

See [LICENSE](LICENSE) file.


## Integration Guide

Autogram Portal provides a complete API solution for applications that need electronic signature capabilities without managing the complexity of digital signing infrastructure.

### Resources

- **API Documentation** - [/api/v1](https://agp.dev.slovensko.digital/api/v1/) (Swagger UI) or `public/openapi.yaml`
- **SDK Examples** - [public/sdk-example.html](https://agp.dev.slovensko.digital/sdk-example.html)
- **API Environment** - Set `API_SKIP_AUTH=true` in `.env` to skip JWTs in local development
- **Process documentation** - [/docs](https://agp.dev.slovensko.digital/docs)
- **Federation architecture** - [docs/federation.md](docs/federation.md)

### How It Works

1. **Create Contracts** - Your app sends documents via API to create a Bundle of Contracts
  - Each Bundle can contain one or more Contracts (typically one)
  - Each Contract can contain multiple Documents (rare, only if needed for single ASiC-E container)
  - You receive UUIDs for the bundle and contracts to track them

2. **Get Notified** - When signing is complete, you're notified via:
  - **Webhooks** - Receive callbacks at your specified URL (using [Standard Webhooks](https://github.com/standard-webhooks/standard-webhooks/blob/main/spec/standard-webhooks.md) specification)
  - **Polling** - Check bundle/contract status via API

3. **Download Results** - Retrieve signed files and optionally delete records from the portal

### User Signing Options

Choose how end users will sign:

**Option A: Redirect to Portal**
- Send users a link to the Autogram Portal
- They complete the entire signing process on our platform
- No integration needed beyond API calls

**Option B: Embedded Signing (SDK)**
- Embed signing interface in your app using our JavaScript SDK
- Display as iframe (embedded) or popup overlay
- See [sdk-example.html](https://agp.dev.slovensko.digital/sdk-example.html) for complete implementation examples
- Supports both individual contracts and bundles

**Option C: Email Notifications** *(planned)*
- Specify recipients when creating bundle/contract
- Portal automatically sends emails with signing links and instructions


### Federation Between Portals

Autogram Portal can route signing requests across portal instances. The current implementation uses two different trust decisions:

- sender-side routing is explicit, because a sender chooses a trusted home portal for a federated recipient
- recipient-side pasted-link opening is dynamic, because a recipient can paste an origin link into their own portal even if that origin portal was not preconfigured locally

**How it works**

1. Admins register the home portals that local senders are allowed to target when creating federated recipients.
2. The sender creates a bundle and assigns a recipient either to the local portal or to one of those trusted remote home portals.
3. The origin portal still creates the canonical signing link, typically `/bundles/:bundle_uuid/sign?recipient=:recipient_uuid`.
4. The recipient can either open that link directly on the origin portal or paste it into their own portal at `/federation/requests/open`.
5. The recipient's home portal discovers the origin portal from the pasted URL, loads `/.well-known/autogram-portal.json`, and checks that the origin supports the federation preview and claim APIs.
6. The home portal asks the origin portal for a preview of the request and, after local sign-in, sends a signed federation claim request.
7. The origin portal verifies that the claiming home portal matches the portal assigned to that recipient. If accepted, it returns a short-lived sign URL containing `grant=...`.
8. The recipient is redirected back to the origin portal, which validates the grant and continues with the standard signing flow.

**Which requests are used**

- **Origin request URL** - The normal bundle signing link used in emails and copied links.
- **Metadata document** - `/.well-known/autogram-portal.json` exposes issuer, portal name, public key, federation API base URL, supported capabilities, and optional email-domain hints.
- **Preview request** - `GET /api/federation/v1/requests/:recipient_uuid` fetches a user-facing preview of a pasted origin request.
- **Claim request** - `POST /api/federation/v1/requests/:recipient_uuid/claim` exchanges the locally authenticated user for a short-lived origin sign URL.
- **Grant-backed sign URL** - The claim response returns the actual signing URL with `grant=...`. This token is short-lived and tied to a stored access-grant record.

**Security model**

- Sender-side routing uses an explicitly configured trusted portal list. This is how the origin portal decides which home portal is allowed to claim a federated recipient.
- Recipient-side pasted-link opening is more permissive: the home portal may dynamically discover an origin portal from its metadata document without a preconfigured local trust record.
- Portal-to-portal requests use a dedicated JWT assertion with `iss`, `aud`, `exp`, `jti`, and `scope` claims.
- The origin portal remains the source of truth for recipient state, signing rules, bundle completion, and signed documents, and it still decides which home portal is allowed to claim each federated recipient.
- Access grants are revoked when the recipient is withdrawn or no longer needed because the bundle has already completed.

**Current scope**

The current implementation lets a recipient paste and claim a foreign request on their own portal even if the origin portal was not preconfigured locally, but the actual signing still completes on the origin portal.

### Federation Configuration

- `FEDERATION_BASE_URL` - Public base URL this portal advertises to peer portals
- `FEDERATION_ISSUER` - Stable issuer identifier used in federation metadata and JWT assertions
- `FEDERATION_PORTAL_NAME` - Display name exposed in federation metadata
- `FEDERATION_PUBLIC_KEY_PEM` - Public key advertised to peer portals
- `FEDERATION_PRIVATE_KEY_PEM` - Private key used to sign outgoing federation assertions
- `FEDERATION_EMAIL_DOMAINS` - Optional comma-separated email domains advertised in federation metadata

### Quick Start

**1. Authentication**

API uses RS256 JWT tokens. See [API documentation](https://agp.dev.slovensko.digital/api/v1/) for authentication details.

**2. Create a Bundle**

```bash
curl -X POST https://agp.dev.slovensko.digital/api/v1/bundles \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -d '{
    "id": "500927d7-47fa-43fd-bda4-547e703a3a4b",
    "contracts": [
      {
        "allowedMethods": ["qes"],
        "documents": [
          {
            "filename": "contract.txt",
            "content": "Sample text content",
            "contentType": "text/plain"
          }
        ],
        "signatureParameters": {
          "format": "XAdES",
          "container": "ASiC_E"
        }
      }
    ],
    "webhook": {
      "url": "https://example.com/webhook"
    }
  }'
```

**3. Integrate Signing UI** *(optional)*

```html
// load Autogram Portal SDK.js
<script src="https://agp.dev.slovensko.digital/sdk.js"></script>
<script>
  // Show bundle in popup mode
  agp.initBundleIframe('500927d7-47fa-43fd-bda4-547e703a3a4b', {
    mode: 'popup',
    popupTitle: 'Sign Document'
  });

  // Or embedded in your page
  agp.initBundleIframe('500927d7-47fa-43fd-bda4-547e703a3a4b', {
    mode: 'iframe',
    parentElement: '#signing-container',
    height: '600px'
  });
</script>
```


---

Made by [slovensko.digital](https://slovensko.digital)


