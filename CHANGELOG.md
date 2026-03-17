# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/ryanbooz/bluebox-docker/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/ryanbooz/bluebox-docker/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ryanbooz/bluebox-docker/releases/tag/v1.0.0
