-- Load rental data from gzipped CSV file
-- This runs during database initialization

-- Connect to bluebox database as postgres (superuser)
-- Required for COPY FROM PROGRAM (needs pg_execute_server_program privilege)
\c bluebox postgres

\set ON_ERROR_STOP on

-- Load rental data from the gzipped CSV
-- Using PROGRAM to decompress on the fly
COPY bluebox.rental (
    rental_id,
    rental_period,
    inventory_id,
    customer_id,
    last_update,
    store_id
)
FROM PROGRAM 'gunzip -c /docker-entrypoint-initdb.d/07-rental-data.csv.gz'
WITH (
    FORMAT csv,
    HEADER true,
    DELIMITER ','
);

-- Log the number of rentals loaded
DO $$
DECLARE
    rental_count bigint;
BEGIN
    SELECT COUNT(*) INTO rental_count FROM bluebox.rental;
    RAISE NOTICE 'Loaded % rental records from CSV', rental_count;
END $$;
