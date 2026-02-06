-- ===========================================
-- Bluebox Database Initialization
-- Step 1: Create roles and database
-- ===========================================
-- Run as postgres superuser in postgres database

\echo '=== Creating roles ==='

-- Schema owner role (for DDL and object management)
CREATE ROLE bluebox_admin WITH 
    NOLOGIN 
    CREATEDB 
    CREATEROLE;
COMMENT ON ROLE bluebox_admin IS 'Schema owner - DDL and object management';

-- Application role (for DML operations)
CREATE ROLE bluebox_app WITH 
    NOLOGIN;
COMMENT ON ROLE bluebox_app IS 'Application role - DML operations only';

-- Login users that inherit from roles
CREATE ROLE bb_admin WITH 
    LOGIN 
    PASSWORD 'admin_password'
    IN ROLE bluebox_admin;
COMMENT ON ROLE bb_admin IS 'Login user for schema administration';

ALTER ROLE bb_admin SET search_path TO bluebox, public;

CREATE ROLE bb_app WITH 
    LOGIN 
    PASSWORD 'app_password'
    IN ROLE bluebox_app;
COMMENT ON ROLE bb_app IS 'Login user for application queries';

ALTER ROLE bb_admin SET search_path TO bluebox, public;
ALTER ROLE bb_app SET search_path TO bluebox, public;

\echo '=== Creating database ==='

-- Create database owned by admin role
CREATE DATABASE bluebox OWNER bluebox_admin;

-- Grant connect to app role
GRANT CONNECT ON DATABASE bluebox TO bluebox_app;

\echo '=== Setting up pg_cron ==='

-- pg_cron must be created in postgres database
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Grant cron visibility to admin
GRANT USAGE ON SCHEMA cron TO bluebox_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA cron TO bluebox_admin;

\echo '=== Switching to bluebox database as role bluebox_admin ==='
\c bluebox bb_admin

\echo '=== Setting default privileges ==='
SET ROLE bluebox_admin;

CREATE SCHEMA IF NOT EXISTS bluebox;

-- Tables: app role gets DML
ALTER DEFAULT PRIVILEGES FOR ROLE bluebox_admin IN SCHEMA bluebox
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO bluebox_app;

-- Sequences: app role can use them
ALTER DEFAULT PRIVILEGES FOR ROLE bluebox_admin IN SCHEMA bluebox
    GRANT USAGE, SELECT ON SEQUENCES TO bluebox_app;

-- Functions/Procedures: app role can execute
ALTER DEFAULT PRIVILEGES FOR ROLE bluebox_admin IN SCHEMA bluebox
    GRANT EXECUTE ON FUNCTIONS TO bluebox_app;

-- Grant schema usage to app role
GRANT USAGE ON SCHEMA bluebox TO bluebox_app;

\echo '=== Step 1 complete ==='
