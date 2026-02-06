-- Load payment data from gzipped CSV file
-- This runs during database initialization
-- Must run after rental data is loaded (foreign key dependency)

-- Connect to bluebox database as postgres (superuser)
-- Required for COPY FROM PROGRAM (needs pg_execute_server_program privilege)
\c bluebox postgres

\set ON_ERROR_STOP on

-- Load payment data from the gzipped CSV
-- Using PROGRAM to decompress on the fly
COPY bluebox.payment (
    payment_id,
    customer_id,
    rental_id,
    amount,
    payment_date
)
FROM PROGRAM 'gunzip -c /docker-entrypoint-initdb.d/07-payment-data.csv.gz'
WITH (
    FORMAT csv,
    HEADER true,
    DELIMITER ','
);

-- Log the number of payments loaded
DO $$
DECLARE
    payment_count bigint;
BEGIN
    SELECT COUNT(*) INTO payment_count FROM bluebox.payment;
    RAISE NOTICE 'Loaded % payment records from CSV', payment_count;
END $$;
