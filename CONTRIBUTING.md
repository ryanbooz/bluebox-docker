# Contributing to Bluebox Docker

This document covers how to update the seed data and test the Docker images locally.

## Updating Seed Data

When the Bluebox schema or data generation logic changes, the compressed data dumps in `init/` need to be regenerated. Here's the workflow:

### Prerequisites

- A running Bluebox PostgreSQL instance with up-to-date data (schema, reference data, and rental history)
- `pg_dump` and `psql` available locally
- Docker installed (for testing the build)

### Step 1: Generate fresh data dumps

From the project root, run:

```bash
./scripts/generate-dumps.sh
```

This connects to your running Bluebox database and exports:
- The full database schema (`03-schema.sql`)
- Compressed data dumps for reference data, customers, inventory, rentals, payments, and the customer status log

Rental and payment data is exported as a rolling 15-month window.

All SQL dump files (schema and data) automatically get cross-version compatibility fixes applied:
- `\c bluebox bb_admin` header to connect to the correct database/role
- `transaction_timeout` commented out (a PG 17+ parameter that breaks older versions)

By default, the script connects to `localhost:5432` as `postgres` against the `bluebox` database. Override with environment variables if needed:

```bash
PGHOST=myhost PGPORT=5433 DB_NAME=bluebox DB_USER=postgres ./scripts/generate-dumps.sh
```

### Step 2: Review 03-schema.sql closely
Depending on your tools and other factors that might be specific to a Postgres version, it's imperative that you review the schema file closely. For now, most of the data is added through the separate dump files, but pay attention for minor schema changes, object comments that don't get carried through, etc.

I currently use tools like Flyway Desktop Enterprise or postgresCompare to verify changes to the schema and they may miss nuances for things that those tools don't currently support.

### Step 3: Test the build locally

```bash
./scripts/test-build.sh
```

This builds the Docker image, starts a container, waits for initialization, and verifies that all data loaded correctly (row counts, foreign key integrity, pg_cron jobs, etc.).

To test a specific PostgreSQL version:

```bash
PG_VERSION=17 ./scripts/test-build.sh
```

To test the development image (PG 19 from source):

```bash
./scripts/test-build-dev.sh
```

### Step 4: Commit and push

Once the test passes, commit the updated files in `init/` and push. The GitHub Actions workflow builds multi-architecture images for PostgreSQL versions 14-18 and pushes them to GHCR.

## Long-lived Dev Instance

For day-to-day work, you can run a dev container that is completely isolated from test scripts. It uses a separate Docker volume (`bluebox-pgdata-dev`) that `test-build.sh` and `docker-compose down -v` won't touch.

```bash
./dev.sh up        # Start the dev container
./dev.sh down      # Stop it (data is kept)
./dev.sh update    # Pull latest image and restart (data is kept)
./dev.sh psql      # Connect with psql as bb_admin
./dev.sh logs      # Follow container logs
./dev.sh status    # Show container status
./dev.sh destroy   # Remove container AND volume (asks for confirmation)
```

This uses `docker-compose.dev.yaml` as an override on top of the main `docker-compose.yaml`, so all PostgreSQL settings (memory, extensions, auto_explain, etc.) stay in sync.

## Other Scripts

- **`scripts/backfill.sh`** - Fills gaps in rental data on a live Bluebox instance. Useful if the database has been idle and you need to generate history before re-dumping. Supports the same `PGHOST`/`PGPORT`/`DB_NAME`/`DB_USER` environment variables.

## CI/CD

The GitHub Actions workflow (`.github/workflows/build-and-push.yml`) handles:
- Building images for PG 14, 15, 16, 17, and 18 on push to `main`
- Building the PG 19-dev image weekly from the PostgreSQL master branch
- Multi-architecture builds (amd64 + arm64)
- Publishing to `ghcr.io/ryanbooz/bluebox-postgres`
