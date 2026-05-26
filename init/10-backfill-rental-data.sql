--
-- Backfill rental history from last known rental to yesterday.
-- Runs before cron setup so ongoing generation has continuous data.
--
-- Small gaps are backfilled automatically during startup. Large gaps are
-- skipped (and the manual command is printed instead) so a stale image
-- doesn't block the container past the healthcheck's start_period while
-- generating weeks of history. See BACKFILL_THRESHOLD_DAYS below.
--
\c bluebox postgres

DO $$
DECLARE
    v_last_rental_date DATE;
    v_backfill_end     DATE := CURRENT_DATE - 1;  -- today is handled by cron
    v_days_to_backfill INT;
    -- Gaps larger than this are left for the operator to run manually.
    v_threshold        CONSTANT INT := 15;
BEGIN
    RAISE NOTICE '================================================';
    RAISE NOTICE 'Rental Backfill Check';
    RAISE NOTICE '================================================';

    SELECT MAX(lower(rental_period)::date) INTO v_last_rental_date
    FROM bluebox.rental;

    IF v_last_rental_date IS NULL THEN
        RAISE NOTICE 'No existing rentals found. Skipping backfill.';
        RAISE NOTICE '================================================';
        RETURN;
    END IF;

    v_days_to_backfill := v_backfill_end - v_last_rental_date;

    RAISE NOTICE 'Last rental date:  %', v_last_rental_date;
    RAISE NOTICE 'Backfill end date: %', v_backfill_end;
    RAISE NOTICE 'Days to backfill:  %', v_days_to_backfill;
    RAISE NOTICE '------------------------------------------------';

    IF v_days_to_backfill <= 0 THEN
        RAISE NOTICE 'No backfill needed - rental data is current.';
        RAISE NOTICE '================================================';
        RETURN;
    END IF;

    IF v_days_to_backfill <= v_threshold THEN
        RAISE NOTICE 'Starting backfill from % to %...', v_last_rental_date + 1, v_backfill_end;
        CALL bluebox.generate_rental_history(
            p_start_date := v_last_rental_date + 1,
            p_end_date := v_backfill_end,
            p_print_debug := TRUE
        );
        RAISE NOTICE '------------------------------------------------';
        RAISE NOTICE 'Backfill complete.';
        RAISE NOTICE '================================================';
        RETURN;
    END IF;

    -- Gap exceeds the threshold: skip auto-backfill so startup stays fast.
    RAISE NOTICE 'Gap of % days exceeds the auto-backfill threshold (% days).', v_days_to_backfill, v_threshold;
    RAISE NOTICE 'Skipping automatic backfill so the container becomes healthy quickly.';
    RAISE NOTICE '';
    RAISE NOTICE 'Once the container is ready, backfill manually with:';
    RAISE NOTICE '  docker exec -it <container> psql -U postgres -d bluebox -c "CALL bluebox.generate_rental_history(p_start_date => DATE ''%'', p_end_date => DATE ''%'')"', v_last_rental_date + 1, v_backfill_end;
    RAISE NOTICE '';
    RAISE NOTICE 'generate_rental_history accepts at most 366 days per call.';
    RAISE NOTICE 'For a larger gap, run it in consecutive <=366-day chunks.';
    RAISE NOTICE '================================================';
END $$;
