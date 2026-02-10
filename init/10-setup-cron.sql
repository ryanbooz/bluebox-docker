-- ===========================================
-- Bluebox Database Initialization
-- Step 9: Setup pg_cron jobs
-- ===========================================
-- Run in postgres database (where pg_cron lives)

\c postgres

\echo '=== Setting up cron jobs ==='

-- Every 5 minutes: generate new open rentals
-- Start inactive, will activate after backfill is complete
SELECT cron.schedule_in_database(
    'generate-rentals', 
    '*/5 * * * *', 
    $$CALL bluebox.generate_rentals(
        p_start_time := now() - interval '5 minutes',
        p_end_time := now(),
        p_close_rentals := false
    )$$,
    'bluebox'
);

-- Every 15 minutes: complete some open rentals
SELECT cron.schedule_in_database(
    'complete-rentals', 
    '*/15 * * * *', 
    $$CALL bluebox.complete_rentals(
        p_min_rental_age := '16 hours',
        p_completion_pct := 15.0
    )$$,
    'bluebox'
);

-- Daily at 2 AM UTC: process lost rentals (30+ days overdue)
SELECT cron.schedule_in_database(
    'process-lost', 
    '0 2 * * *', 
    $$CALL bluebox.process_lost_rentals(
        p_lost_after := '30 days',
        p_suspend_customer := true
    )$$,
    'bluebox'
);

-- Daily at 3 AM UTC: update customer activity
SELECT cron.schedule_in_database(
    'customer-activity', 
    '0 3 * * *', 
    $$CALL bluebox.update_customer_activity(
        dormant_days := 180,
        reactivate_pct := 0.5
    )$$,
    'bluebox'
);

-- Weekly Sunday at 4 AM UTC: rebalance inventory
SELECT cron.schedule_in_database(
    'rebalance-inventory', 
    '0 4 * * 0', 
    $$CALL bluebox.rebalance_inventory(
        max_moves_per_run := 10000
    )$$,
    'bluebox'
);

-- Daily at 1 AM UTC: analyze key tables
SELECT cron.schedule_in_database(
    'analyze-tables', 
    '0 1 * * *', 
    $$ANALYZE bluebox.rental; 
    ANALYZE bluebox.payment; 
    ANALYZE bluebox.inventory;$$,
    'bluebox'
);

\echo '=== Verifying cron jobs ==='

SELECT jobid, jobname, schedule, database 
FROM cron.job 
ORDER BY jobid;

\echo '=== Step 9 complete ==='
\echo 'Cron jobs will begin running automatically.'
\echo 'New rentals will appear within 5 minutes.'
