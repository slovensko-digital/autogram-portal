# Autogram Portal

Web application for managing digital signatures and document contracts.

**Staging:** [agp.dev.slovensko.digital](https://agp.dev.slovensko.digital)

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

We are using GoodJob for job queue. Admin at [/admin/good_job](http://localhost:3000/admin/good_job)

## Configuration

Edit `.env` file:
- `API_SKIP_AUTH=true` - Skip auth in development
- `AUTOGRAM_SERVICE_URL` - Autogram service URL
- `AVM_URL` - Autogram AVM service URL

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


