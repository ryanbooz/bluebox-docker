# Bluebox Docker

A PostgreSQL sample database simulating a video rental kiosk business (think Redbox). Includes realistic, continuously-updating data for learning SQL, PostgreSQL administration, and data analysis.

## Features

- **Realistic data model**: Films, customers, stores, inventory, rentals, payments
- **Continuous data generation**: pg_cron jobs create new rentals every 5 minutes
- **Geographic data**: PostGIS-enabled with store/customer locations
- **Customer lifecycle**: Churn, reactivation, and status tracking
- **Multiple PostgreSQL versions**: 15, 16, 17, 18, and 19-dev (built from master)
- **Multi-architecture**: AMD64 and ARM64 (native Apple Silicon support)
- **Pre-loaded extensions**: PostGIS, pg_stat_statements, hypopg, pgvector, TimescaleDB, and more

## Overview
The motivation for this "ready to go" Docker container is primarily testing and training. The schema will continue to undergo changes which can be tracked in the separate [Bluebox Schema repository](https://github.com/ryanbooz/bluebox).

Once you have cloned this repository and started the container as described below, you'll have:

- Postgres running at the latest patch version of your selected major version
- Bluebox database populated with sample data including customers, films, inventory, stores, and staff
- Rental history automatically backfilled from the last snapshot date through yesterday
- Automated pg_cron jobs that generate new rentals and payments in real-time (see Automated Jobs below)
- Three users: postgres (superuser), bb_admin (application user with schema ownership), bb_app (application user with DML privileges)

The database simulates a video rental business with geographically distributed customers and stores across the United States. Rental activity varies by day, with increased volume on holidays.

## Quick Start

The easiest way to get started is with the interactive startup script:

```bash
./start.sh
```

This will prompt you for the Postgres version and port, then start the container.

## Manual Setup

If you prefer to run commands directly:

```bash
# Set your preferred version and port
export PG_VERSION=18
export PG_PORT=5432

# Start the container (project name keeps instances separate)
docker-compose -p bluebox-pg${PG_VERSION} up -d
```

## Running Multiple Versions

You can run multiple Postgres versions simultaneously. Each needs a unique port and project name:

```bash
# Start Postgres 18 on default port
PG_VERSION=18 PG_PORT=5432 docker-compose -p bluebox-pg18 up -d

# Start Postgres 17 on the next available port
PG_VERSION=17 PG_PORT=5433 docker-compose -p bluebox-pg17 up -d

# Start the dev version on another port
PG_VERSION=19-dev PG_PORT=5434 docker-compose -p bluebox-pg19-dev up -d
```

All containers will run independently with their own data volumes.

## Available Images

| Tag | PostgreSQL | Type | Architectures |
|-----|------------|------|---------------|
| `18`, `latest` | 18.x | Stable | amd64, arm64 |
| `17` | 17.x | Stable | amd64, arm64 |
| `16` | 16.x | Stable | amd64, arm64 |
| `15` | 15.x | Stable | amd64, arm64 |
| `19-dev`, `dev` | master | Development | amd64, arm64 |

Pull directly:
```bash
# Stable versions
docker pull ghcr.io/ryanbooz/bluebox-postgres:18
docker pull ghcr.io/ryanbooz/bluebox-postgres:17

# Development version (built from PostgreSQL master branch)
docker pull ghcr.io/ryanbooz/bluebox-postgres:19-dev
```

> ⚠️ **Note**: The `19-dev` image is built from PostgreSQL's master branch and is for testing upcoming features only. It rebuilds weekly and may contain bugs. Do not use for production.

## Connection Details

| User | Password | Purpose |
|------|----------|---------|
| `bb_app` | `app_password` | Application queries (SELECT, INSERT, UPDATE, DELETE) |
| `bb_admin` | `admin_password` | Schema administration (DDL, maintenance) |
| `postgres` | `password` | Superuser (pg_cron setup, emergencies only) |

## Backfill Historical Data

When the initial container starts, it will backfill any days that do not have rental data from the last known rental until "yesterday". There are `pg_cron` jobs that create new rental data every 5 minutes starting with "now". As long as the container is running, you should continue to get new rental data every 5 minutes.

However, there may be times where the container is shut down for multiple days and you'd like to get it "caught up" to today. 

To fill the gap between the last rental and today, connect to the database with `psql` or your IDE of choice, and run the following:

```bash
# Or manually
docker exec -it bluebox-18 psql -U bb_admin -d bluebox -c "
    CALL bluebox.generate_rental_history(
        p_start_date := '2026-01-15'::date,  -- adjust to day after last rental
        p_end_date := CURRENT_DATE - 1,
        p_print_debug := true
    );
"
```

## Automated Jobs (pg_cron)

| Job | Schedule | Description |
|-----|----------|-------------|
| `generate-rentals` | Every 5 min | Create new open rentals |
| `complete-rentals` | Every 15 min | Close rentals, generate payments |
| `process-lost` | Daily 2 AM | Mark 30+ day overdue as lost |
| `customer-activity` | Daily 3 AM | Churn inactive, random win-back |
| `rebalance-inventory` | Weekly Sun 4 AM | Redistribute inventory |
| `analyze-tables` | Daily 1 AM | Update table statistics |

### Manage Jobs

```sql
-- View jobs (connect to postgres database)
\c postgres
SELECT jobid, jobname, schedule, active FROM cron.job;

-- Pause all jobs
UPDATE cron.job SET active = false;

-- Resume all jobs
UPDATE cron.job SET active = true;

-- View recent runs
SELECT jobid, start_time, end_time, status 
FROM cron.job_run_details 
ORDER BY start_time DESC LIMIT 20;
```

## Key Procedures

```sql
-- Generate rentals (for cron, ≤24 hours)
CALL bluebox.generate_rentals(
    p_start_time := now() - interval '5 minutes',
    p_end_time := now(),
    p_close_rentals := false,
    p_print_debug := true
);

-- Generate historical data (multi-day backfill)
CALL bluebox.generate_rental_history(
    p_start_date := '2026-01-01',
    p_end_date := '2026-01-31',
    p_print_debug := true
);

-- Complete open rentals
CALL bluebox.complete_rentals(
    p_min_rental_age := '16 hours',
    p_completion_pct := 15.0,
    p_print_debug := true
);

-- Process lost items
CALL bluebox.process_lost_rentals(
    p_lost_after := '30 days',
    p_suspend_customer := true,
    p_print_debug := true
);
```

## Sample Queries

```sql
-- Current status
SELECT 
    (SELECT count(*) FROM bluebox.rental WHERE upper(rental_period) IS NULL) as open_rentals,
    (SELECT count(*) FROM bluebox.customer WHERE activebool) as active_customers,
    (SELECT count(*) FROM bluebox.inventory WHERE status_id = 1) as inventory_available;

-- Daily rental volume
SELECT 
    lower(rental_period)::date as day,
    count(*) as rentals,
    sum(p.amount) as revenue
FROM bluebox.rental r
JOIN bluebox.payment p USING (rental_id)
WHERE lower(rental_period) > now() - interval '7 days'
GROUP BY 1 ORDER BY 1;

-- Top rented films
SELECT f.title, count(*) as rentals
FROM bluebox.rental r
JOIN bluebox.inventory i USING (inventory_id)
JOIN bluebox.film f USING (film_id)
WHERE lower(rental_period) > now() - interval '30 days'
GROUP BY f.film_id, f.title
ORDER BY rentals DESC
LIMIT 10;

-- Customer churn analysis
SELECT 
    date_trunc('month', status_date) as month,
    count(*) FILTER (WHERE reason_code = 'inactivity') as churned,
    count(*) FILTER (WHERE reason_code = 'winback') as reactivated
FROM bluebox.customer_status_log
WHERE reason_code IN ('inactivity', 'winback')
GROUP BY 1 ORDER BY 1;
```

## Building Locally

```bash
# Build the image
docker build -t bluebox-postgres:18 .

# Or with docker-compose
docker-compose build
```

## Extensions Included
The following extensions are included when available. Not all extensions are updated for development branches of Postgres
or newly released stable versions.

- PostGIS 3.x
- pg_stat_statements
- pg_cron
- hypopg
- pgvector
- TimescaleDB
- pg_hint_plan
- pgaudit
- pg_repack
- hll
- postgresql_anonymizer

## Related Projects

- [Bluebox Schema](https://github.com/ryanbooz/bluebox) - Flyway migrations and schema documentation

## License

PostgreSQL License (see [LICENSE](LICENSE))
