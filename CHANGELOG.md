# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.3] - 2026-04-06

### Changed
- `docker-compose.yaml`: container name and volume name are now configurable via
  `BLUEBOX_CONTAINER_NAME` and `BLUEBOX_VOLUME_NAME` env vars, preventing
  collisions between test builds and long-running instances
- `test-build.sh`: uses isolated Compose project name, container name, and volume
  so test builds no longer interfere with running containers
- `test-build.sh`: improved init progress display (dots on same line as script name)
- `generate-dumps.sh`: backs up existing init files before overwriting
- Added Dependabot configuration for Docker base images and GitHub Actions

### Fixed
- 19-dev image: switched PostGIS back to master branch for PG 19 compatibility
  (stable PostGIS releases don't yet support PG 19-dev header changes)
- 19-dev image: disabled pg_cron (does not compile against PG 19-dev due to
  C23 typeof changes in c.h); cron-based data generation is unavailable on
  the dev image until pg_cron adds PG 19 support

## [1.1.2] - 2026-03-17

### Fixed
- Fixed sequence sync issue with identity columns causing duplicate key errors
  during backfill after initial data load

## [1.1.1] - 2026-03-17

### Changed
- minor improvements in `generate-dump.sh` and `test-build.sh`
- updated `generate_rental_history` procedure to improve the speed of 
  data generation. This particularly helps the initial startup of a new
  Docker container when the included data is more than a few weeks old
- Fixed overlooked conversion of old sequence columns to IDENTITY columns
  in `inventory` and `payment`
- Updated films to current commit date and generated rental data up to commit date

## [1.1.0] - 2026-02-18

### Fixed
- Object ownership: schema objects are now correctly owned by `bluebox_admin`,
  ensuring `bb_app` gets proper permissions via DEFAULT PRIVILEGES

### Changed
- `test-build.sh` automatically uses the locally built image via `BLUEBOX_IMAGE`
  env var (no more forgetting to switch `docker-compose.yaml`)
- `generate-dumps.sh` auto-injects `SET ROLE` statements into the schema dump
  for correct object ownership
- `start.sh` shows init script progress during startup instead of only dots
- `test-build.sh` shows init script progress during data load verification
- `docker-compose.yaml` image is now configurable via `BLUEBOX_IMAGE` env var
  (defaults to `ghcr.io/ryanbooz/bluebox-postgres`, no change for existing users)
- Updated all scripts and documentation to use `docker compose` (Compose V2)
  instead of the deprecated `docker-compose` (Compose V1)

## [1.0.0] - 2026-02-10

### Added
- Initial public release of Bluebox Docker
- Support for PostgreSQL versions 14, 15, 16, 17, and 18
- PostgreSQL 19-dev (master branch) development build support
- Pre-loaded sample data: films, customers, stores, inventory, rentals, payments
- Automated data generation via pg_cron (rentals every 5 minutes)
- Customer lifecycle tracking (churn, reactivation, status logs)
- Pre-installed extensions:
  - PostGIS 3.x for geographic data
  - pg_stat_statements for query performance monitoring
  - pg_cron for scheduled jobs
  - hypopg for hypothetical index analysis
  - pgvector for vector similarity search
  - TimescaleDB for time-series data
  - pg_hint_plan for query plan control
  - pgaudit for audit logging
  - pg_repack for table/index reorganization
  - hll for HyperLogLog cardinality estimation
  - postgresql_anonymizer for data anonymization
- Multi-architecture support (amd64, arm64)
- Role-based access control (bb_admin, bb_app, postgres)
- Interactive `start.sh` launcher with version/port selection
- `dev.sh` for long-lived development instances
- CSV data loading from compressed files during initialization
- Comprehensive test scripts for build validation

[Unreleased]: https://github.com/ryanbooz/bluebox-docker/compare/v1.1.3...HEAD
[1.1.3]: https://github.com/ryanbooz/bluebox-docker/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/ryanbooz/bluebox-docker/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/ryanbooz/bluebox-docker/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/ryanbooz/bluebox-docker/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ryanbooz/bluebox-docker/releases/tag/v1.0.0
