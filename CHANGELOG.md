# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release of Bluebox Docker
- Support for PostgreSQL versions 15, 16, 17, and 18
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
- Comprehensive test scripts for build validation
- CSV data loading from compressed files during initialization
- Cross-version compatibility fixes for PostgreSQL 15-19

### Technical Details
- Dockerfile for stable PostgreSQL releases (15-18)
- Dockerfile.dev for building from PostgreSQL master branch
- Automated init scripts for database setup and data loading
- Helper scripts: backfill.sh, generate-dumps.sh, test-build.sh, test-build-dev.sh
- Optimized checkpoint configuration for faster data loads
- Role-based access control (bb_admin, bb_app, postgres)

## [1.0.0] - YYYY-MM-DD

### Note
Version 1.0.0 will be tagged upon first release to GitHub Container Registry.

[Unreleased]: https://github.com/ryanbooz/bluebox-docker/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/ryanbooz/bluebox-docker/releases/tag/v1.0.0
