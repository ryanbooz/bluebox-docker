#!/bin/bash
# ===========================================
# Generate Bluebox Data Dumps
# ===========================================
# Run this to create fresh data dumps for the Docker image
# Generates rolling 12-15 months of rental/payment data

set -e

DB_NAME="${DB_NAME:-bluebox}"
DB_USER="${DB_USER:-postgres}"
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
OUTPUT_DIR="${OUTPUT_DIR:-./init}"

# Calculate date range (last 15 months)
CUTOFF_DATE=$(date -d "15 months ago" +%Y-%m-%d 2>/dev/null || \
              date -v-15m +%Y-%m-%d)

# Helper: prepend database connection and fix PG 17+ compatibility
# Used for pg_dump data files that need \c and transaction_timeout patched
fix_dump() {
    printf '%s\n\n' '\c bluebox bb_admin'
    awk '{
        if ($0 == "SET transaction_timeout = 0;") {
            print "-- transaction_timeout is a PG 17+ parameter and not necessary for init scripts"
            print "-- SET transaction_timeout = 0;"
        } else {
            print $0
        }
    }'
}

BACKUP_DIR="${OUTPUT_DIR}_backup_$(date +%Y%m%d_%H%M%S)"

echo "=== Bluebox Data Dump Generator ==="
echo "Output directory: $OUTPUT_DIR"
echo "Rental/payment cutoff: $CUTOFF_DATE (data newer than this)"
echo ""

mkdir -p "$OUTPUT_DIR"

# Backup existing init files if any exist
if ls "$OUTPUT_DIR"/*.sql "$OUTPUT_DIR"/*.gz "$OUTPUT_DIR"/*.csv.gz 2>/dev/null | grep -q .; then
    echo "Backing up existing init files to: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    cp "$OUTPUT_DIR"/*.sql "$OUTPUT_DIR"/*.gz "$OUTPUT_DIR"/*.csv.gz "$BACKUP_DIR/" 2>/dev/null || true
    echo "  ✓ Backup created"
    echo ""
fi

# 03 - Schema (structure only, no privileges/ownership)
echo "Dumping schema..."
{
    printf '%s\n' '\c bluebox postgres'
    printf '\n%s\n\n' "\\echo '=== Creating schema ==='"
    pg_dump -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" \
        --schema-only -x -O
} > "$OUTPUT_DIR/03-schema.sql"

# Post-process the schema dump:
#   - Comment out transaction_timeout (PG 17+ only)
#   - Inject SET ROLE bluebox_admin after each SET block (so objects get correct ownership)
#   - Inject SET ROLE postgres before extensions (need superuser for CREATE EXTENSION)
awk '
BEGIN { set_block = 0; seen_extension = 0 }
{
    # Comment out transaction_timeout
    if ($0 == "SET transaction_timeout = 0;") {
        print "-- transaction_timeout is a PG 17+ parameter and not necessary for init scripts"
        print "-- SET transaction_timeout = 0;"
        next
    }

    # Before first CREATE EXTENSION, switch to superuser
    if (/^CREATE EXTENSION/ && !seen_extension) {
        seen_extension = 1
        print "-- Connect as superuser for extension creation"
        print "SET ROLE postgres;"
        print ""
    }

    print $0

    # After each SET row_security = off, inject SET ROLE bluebox_admin
    if ($0 == "SET row_security = off;") {
        set_block++
        print ""
        print "-- Set the role to bluebox_admin for schema and object creation"
        print "-- This ensures all objects are owned by bluebox_admin and all of"
        print "-- the necessary permissions are applied for bluebox_app through default privileges."
        print "SET ROLE bluebox_admin;"
    }
}
' "$OUTPUT_DIR/03-schema.sql" > "$OUTPUT_DIR/03-schema.sql.tmp"
mv "$OUTPUT_DIR/03-schema.sql.tmp" "$OUTPUT_DIR/03-schema.sql"

echo "  ✓ Injected SET ROLE statements for correct object ownership"
echo "  → 03-schema.sql"

# 04 - Reference data (small tables, full dump)
echo "Dumping reference data..."
pg_dump -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" \
    --data-only --no-owner \
    -n bluebox \
    -t bluebox.film \
    -t bluebox.film_genre \
    -t bluebox.film_cast \
    -t bluebox.film_crew \
    -t bluebox.film_production_company \
    -t bluebox.person \
    -t bluebox.production_company \
    -t bluebox.language \
    -t bluebox.release_type \
    -t bluebox.holiday \
    -t bluebox.inventory_status \
    -t bluebox.pricing \
    -t bluebox.store \
    -t bluebox.zip_code_info \
    | fix_dump | gzip > "$OUTPUT_DIR/04-reference-data.sql.gz"
echo "  → 04-reference-data.sql.gz"

# 05 - Customer data (full dump)
echo "Dumping customer data..."
pg_dump -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" \
    --data-only --no-owner \
    -n bluebox \
    -t bluebox.customer \
    | fix_dump | gzip > "$OUTPUT_DIR/05-customer-data.sql.gz"
echo "  → 05-customer-data.sql.gz"

# 06 - Inventory data (full dump)
echo "Dumping inventory data..."
pg_dump -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" \
    --data-only --no-owner \
    -n bluebox \
    -t bluebox.inventory \
    | fix_dump | gzip > "$OUTPUT_DIR/06-inventory-data.sql.gz"
echo "  → 06-inventory-data.sql.gz"

# 07 - Rental and payment data (rolling window)
echo "Dumping rental/payment data (since $CUTOFF_DATE)..."
psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" -c "\
    COPY (
        SELECT * FROM bluebox.rental 
        WHERE lower(rental_period) >= CURRENT_DATE-'15 months'::interval 
            AND lower(rental_period) <= CURRENT_DATE-'2 days'::interval
        ORDER BY rental_id
    ) TO STDOUT WITH CSV HEADER" \
    | gzip > "$OUTPUT_DIR/07-rental-data.csv.gz"
echo "  → 07-rental-data.csv.gz"

psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" -c "\
    COPY (
        SELECT p.* FROM bluebox.payment p
        JOIN bluebox.rental r ON p.rental_id = r.rental_id
        WHERE lower(rental_period) >= CURRENT_DATE-'15 months'::interval 
            AND lower(rental_period) <= CURRENT_DATE-'2 days'::interval
        ORDER BY p.payment_id
    ) TO STDOUT WITH CSV HEADER" \
    | gzip > "$OUTPUT_DIR/07-payment-data.csv.gz"
echo "  → 07-payment-data.csv.gz"

# 08 - Customer status log (full dump)
echo "Dumping customer status log..."
pg_dump -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" \
    --data-only --no-owner \
    -n bluebox \
    -t bluebox.customer_status_log \
    | fix_dump | gzip > "$OUTPUT_DIR/08-customer-status-log.sql.gz"
echo "  → 08-customer-status-log.sql.gz"

echo ""
echo "=== Dump Statistics ==="

# Show row counts and file sizes
echo ""
echo "Row counts:"
psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" <<EOF
SELECT 'rental (since $CUTOFF_DATE)' as table_name, 
       count(*) as rows
FROM bluebox.rental 
WHERE lower(rental_period) >= '$CUTOFF_DATE'::date
UNION ALL
SELECT 'payment (since $CUTOFF_DATE)', count(*)
FROM bluebox.payment p
JOIN bluebox.rental r ON p.rental_id = r.rental_id
WHERE lower(r.rental_period) >= '$CUTOFF_DATE'::date
UNION ALL
SELECT 'customer', count(*) FROM bluebox.customer
UNION ALL
SELECT 'inventory', count(*) FROM bluebox.inventory
UNION ALL
SELECT 'film', count(*) FROM bluebox.film;
EOF

echo ""
echo "File sizes:"
ls -lh "$OUTPUT_DIR"/*.gz | awk '{print "  " $9 ": " $5}'

echo ""
echo "=== Done ==="
echo "Copy these files to init/ in the Docker build context."
