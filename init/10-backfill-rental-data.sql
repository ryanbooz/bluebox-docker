--
-- Backfill rental history from last known rental to yesterday
-- This runs before cron setup to ensure continuous data
--
-- TODO: If the gap exceeds 366 days, generate_rental_history will fail.
--       Add chunking logic to handle gaps larger than 366 days.
--
\c bluebox postgres

DO $$
DECLARE
    v_last_rental_date DATE;
    v_backfill_end DATE;
    v_days_to_backfill INT;
BEGIN
    RAISE NOTICE '================================================';
    RAISE NOTICE 'Rental Backfill Check';
    RAISE NOTICE '================================================';

    -- Get the most recent rental start date
    SELECT MAX(lower(rental_period)::date) INTO v_last_rental_date
    FROM bluebox.rental;

    -- Backfill up to yesterday (today will be handled by cron)
    v_backfill_end := CURRENT_DATE - 1;

    IF v_last_rental_date IS NULL THEN
        RAISE NOTICE 'No existing rentals found. Skipping backfill.';
        RAISE NOTICE '================================================';
        RETURN;
    END IF;

    RAISE NOTICE 'Last rental date: %', v_last_rental_date;
    RAISE NOTICE 'Backfill end date: %', v_backfill_end;

    -- Check if backfill is needed
    IF v_last_rental_date >= v_backfill_end THEN
        RAISE NOTICE 'No backfill needed - rental data is current.';
        RAISE NOTICE '================================================';
        RETURN;
    END IF;

    v_days_to_backfill := v_backfill_end - v_last_rental_date;
    RAISE NOTICE 'Days to backfill: %', v_days_to_backfill;
    RAISE NOTICE '------------------------------------------------';
    RAISE NOTICE 'Starting backfill from % to %...', v_last_rental_date + 1, v_backfill_end;

    -- Run the backfill
    CALL bluebox.generate_rental_history(
        p_start_date := v_last_rental_date + 1,
        p_end_date := v_backfill_end,
        p_print_debug := TRUE
    );

    RAISE NOTICE '------------------------------------------------';
    RAISE NOTICE 'Backfill complete.';
    RAISE NOTICE '================================================';
END $$;