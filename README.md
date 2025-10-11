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

## API

API documentation in `public/api/v1/openapi.yaml` or Swagger served at [/api/v1](http://localhost:3000/api/v1/)

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

---

Made by [slovensko.digital](https://slovensko.digital)


