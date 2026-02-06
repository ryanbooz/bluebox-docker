-- ===========================================
-- Bluebox Database Initialization
-- Step 2: Create extensions (requires superuser)
-- ===========================================

\c bluebox postgres

\echo '=== Creating extensions ==='

-- PostGIS for geographic data
CREATE EXTENSION IF NOT EXISTS postgis;

-- pg_stat_statements for query analysis
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- hypopg for hypothetical indexes
CREATE EXTENSION IF NOT EXISTS hypopg;

-- pgstattuple for table statistics
CREATE EXTENSION IF NOT EXISTS pgstattuple;

-- Grant extension usage to admin
GRANT USAGE ON SCHEMA public TO bluebox_admin;
GRANT USAGE ON SCHEMA public TO bluebox_app;

\echo '=== Step 2 complete ==='
