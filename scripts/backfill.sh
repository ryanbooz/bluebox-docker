#!/bin/bash
# ===========================================
# Bluebox Backfill Script
# ===========================================
# Fills the gap between the last rental in seed data and today
# Run this after initial setup if you want continuous history

set -e

DB_NAME="${DB_NAME:-bluebox}"
DB_USER="${DB_USER:-postgres}"
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"

echo "=== Bluebox Data Backfill ==="
echo ""

# Get the last rental date
LAST_RENTAL=$(psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT max(lower(rental_period))::date FROM bluebox.rental")

TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)

echo "Last rental in seed data: $LAST_RENTAL"
echo "Today: $TODAY"
echo ""

if [[ "$LAST_RENTAL" == "$TODAY" ]] || [[ "$LAST_RENTAL" > "$TODAY" ]]; then
    echo "✓ Data is current. No backfill needed."
    exit 0
fi

# Calculate days to backfill
DAYS_GAP=$(psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" -tAc \
    "SELECT '$TODAY'::date - '$LAST_RENTAL'::date")

echo "Days to backfill: $DAYS_GAP"
echo ""

# Confirm before proceeding
read -p "Proceed with backfill? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "=== Generating historical rentals ==="
echo "This may take a while for large gaps..."
echo ""

# Generate closed rentals for the gap (day after last rental through yesterday)
START_DATE=$(date -d "$LAST_RENTAL + 1 day" +%Y-%m-%d 2>/dev/null || \
             date -v+1d -j -f "%Y-%m-%d" "$LAST_RENTAL" +%Y-%m-%d)

psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" <<EOF
CALL bluebox.generate_rental_history(
    p_start_date := '$START_DATE'::date,
    p_end_date := '$YESTERDAY'::date,
    p_print_debug := true
);
EOF

echo ""
echo "=== Generating open rentals for today ==="

psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" <<EOF
CALL bluebox.generate_rentals(
    p_start_time := now() - interval '12 hours',
    p_end_time := now(),
    p_close_rentals := false,
    p_print_debug := true
);
EOF

echo ""
echo "=== Backfill complete ==="
echo ""

# Show summary
psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" <<EOF
SELECT 
    count(*) as total_rentals,
    count(*) FILTER (WHERE upper(rental_period) IS NULL) as open_rentals,
    min(lower(rental_period))::date as earliest_rental,
    max(lower(rental_period))::date as latest_rental
FROM bluebox.rental;
EOF

echo ""
echo "✓ Done! The cron jobs will continue generating data automatically."
