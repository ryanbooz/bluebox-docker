-- Reset all sequences after bulk data load.
-- Must run AFTER all data-loading init scripts.
\c bluebox postgres

DO $$
BEGIN
    RAISE NOTICE 'Resetting sequences to match loaded data...';

    -- bluebox schema
    PERFORM setval(pg_get_serial_sequence('bluebox.rental',              'rental_id'),   COALESCE(MAX(rental_id),   1)) FROM bluebox.rental;
    PERFORM setval(pg_get_serial_sequence('bluebox.payment',             'payment_id'),  COALESCE(MAX(payment_id),  1)) FROM bluebox.payment;
    PERFORM setval(pg_get_serial_sequence('bluebox.inventory',           'inventory_id'),COALESCE(MAX(inventory_id),1)) FROM bluebox.inventory;
    PERFORM setval(pg_get_serial_sequence('bluebox.person',              'person_id'),   COALESCE(MAX(person_id),   1)) FROM bluebox.person;
    PERFORM setval(pg_get_serial_sequence('bluebox.film_genre',          'genre_id'),    COALESCE(MAX(genre_id),    1)) FROM bluebox.film_genre;
    PERFORM setval(pg_get_serial_sequence('bluebox.customer_status_log', 'log_id'),      COALESCE(MAX(log_id),      1)) FROM bluebox.customer_status_log;
    PERFORM setval(pg_get_serial_sequence('bluebox.staff',               'staff_id'),    COALESCE(MAX(staff_id),    1)) FROM bluebox.staff;
    PERFORM setval(pg_get_serial_sequence('bluebox.language',            'language_id'), COALESCE(MAX(language_id), 1)) FROM bluebox.language;
    PERFORM setval(pg_get_serial_sequence('bluebox.inventory_status',    'status_id'),   COALESCE(MAX(status_id),   1)) FROM bluebox.inventory_status;

    -- staging schema
    PERFORM setval(pg_get_serial_sequence('staging.film_credits', 'id'), COALESCE(MAX(id), 1)) FROM staging.film_credits;

    RAISE NOTICE 'Sequence reset complete.';
END;
$$;