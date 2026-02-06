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

## Quick Start

```bash
# Start with PostgreSQL 18 (default)
docker-compose up -d

# Or specify a version
PG_VERSION=16 docker-compose up -d

# Connect as the application user
psql -h localhost -U bb_app -d bluebox
# Password: app_password

# Check it's working
SELECT count(*) FROM bluebox.rental WHERE upper(rental_period) IS NULL;
```

New rentals will start appearing within 5 minutes.

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

The seed data is current through a specific date. To fill the gap to today:

```bash
# Inside the container
docker exec -it bluebox-18 backfill.sh

# Or manually
docker exec -it bluebox-18 psql -U bb_admin -d bluebox -c "
    CALL bluebox.generate_rental_history(
        p_start_date := '2026-01-15'::date,  -- adjust to day after last rental
        p_end_date := CURRENT_DATE - 1,
        p_print_debug := true
    );
"
```

## Data Model

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    film     │────<│  inventory  │>────│    store    │
└─────────────┘     └─────────────┘     └─────────────┘
                           │
                           │
┌─────────────┐     ┌──────▼──────┐     ┌─────────────┐
│  customer   │────<│   rental    │>────│   payment   │
└─────────────┘     └─────────────┘     └─────────────┘
       │
       ▼
┌─────────────────────┐
│ customer_status_log │
└─────────────────────┘
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

## Refreshing Data Dumps

To generate new data dumps (for updating the image):

```bash
./scripts/generate-dumps.sh
```

This creates compressed dumps of the last 15 months of rental/payment data plus all reference data.

## Extensions Included

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
