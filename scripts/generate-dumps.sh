#!/bin/bash
# ===========================================
# Generate Bluebox Data Dumps
# ===========================================
# Run this to create fresh data dumps for the Docker image
# Generates rolling 12-15 months of rental/payment data

set -e

DB_NAME="${DB_NAME:-bluebox}"
DB_USER="${DB_USER:-bb_admin}"
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
OUTPUT_DIR="${OUTPUT_DIR:-./init}"

# Calculate date range (last 15 months)
CUTOFF_DATE=$(date -d "15 months ago" +%Y-%m-%d 2>/dev/null || \
              date -v-15m +%Y-%m-%d)

echo "=== Bluebox Data Dump Generator ==="
echo "Output directory: $OUTPUT_DIR"
echo "Rental/payment cutoff: $CUTOFF_DATE (data newer than this)"
echo ""

mkdir -p "$OUTPUT_DIR"

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
    | gzip > "$OUTPUT_DIR/04-reference-data.sql.gz"
echo "  → 04-reference-data.sql.gz"

# 05 - Customer data (full dump)
echo "Dumping customer data..."
pg_dump -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" \
    --data-only --no-owner \
    -n bluebox \
    -t bluebox.customer \
    | gzip > "$OUTPUT_DIR/05-customer-data.sql.gz"
echo "  → 05-customer-data.sql.gz"

# 06 - Inventory data (full dump)
echo "Dumping inventory data..."
pg_dump -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" \
    --data-only --no-owner \
    -n bluebox \
    -t bluebox.inventory \
    | gzip > "$OUTPUT_DIR/06-inventory-data.sql.gz"
echo "  → 06-inventory-data.sql.gz"

# 07 - Rental and payment data (rolling window)
echo "Dumping rental/payment data (since $CUTOFF_DATE)..."
psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" -c "\
    COPY (
        SELECT * FROM bluebox.rental 
        WHERE lower(rental_period) >= '$CUTOFF_DATE'::date
        ORDER BY rental_id
    ) TO STDOUT WITH CSV HEADER" \
    | gzip > "$OUTPUT_DIR/07-rental-data.csv.gz"
echo "  → 07-rental-data.csv.gz"

psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$DB_NAME" -c "\
    COPY (
        SELECT p.* FROM bluebox.payment p
        JOIN bluebox.rental r ON p.rental_id = r.rental_id
        WHERE lower(r.rental_period) >= '$CUTOFF_DATE'::date
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
    | gzip > "$OUTPUT_DIR/08-customer-status-log.sql.gz"
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
