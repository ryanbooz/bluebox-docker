#!/bin/bash
# Fix init scripts for cross-version compatibility
# 1. Adds \c bluebox bb_admin to connect to the correct database
# 2. Comments out transaction_timeout (PG 17+ only parameter)

set -e

INIT_DIR="./init"
BACKUP_DIR="./init_backup_$(date +%Y%m%d_%H%M%S)"

echo "=== Fixing init scripts ==="
echo ""

# Create backup
echo "Creating backup at: ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"
cp ${INIT_DIR}/*.sql.gz "${BACKUP_DIR}/" 2>/dev/null || true
echo "✓ Backup created"
echo ""

# Files that need the database connection added
DATA_FILES=(
    "04-reference-data.sql.gz"
    "05-customer-data.sql.gz"
    "06-inventory-data.sql.gz"
    "08-customer-status-log.sql.gz"
)

for file in "${DATA_FILES[@]}"; do
    filepath="${INIT_DIR}/${file}"

    if [ ! -f "$filepath" ]; then
        echo "⚠ Warning: ${file} not found, skipping..."
        continue
    fi

    echo "Processing: ${file}"

    # Decompress
    gunzip "${filepath}"

    # Get uncompressed filename
    uncompressed="${filepath%.gz}"

    # Fix 1: Add database connection if missing
    connection_added=false
    if ! grep -q '\\c bluebox' "${uncompressed}"; then
        # Create temp file with connection command at the top
        tmp_file="${uncompressed}.tmp"
        printf '%s\n\n' '\c bluebox bb_admin' > "${tmp_file}"
        cat "${uncompressed}" >> "${tmp_file}"
        mv "${tmp_file}" "${uncompressed}"
        connection_added=true
        echo "  ✓ Added database connection"
    else
        echo "  - Already has database connection"
    fi

    # Fix 2: Comment out transaction_timeout (PG 17+ parameter)
    timeout_fixed=false
    if grep -q '^SET transaction_timeout = 0;' "${uncompressed}"; then
        # Replace the transaction_timeout line with comments (using awk for portability)
        awk '{
            if ($0 == "SET transaction_timeout = 0;") {
                print "-- transaction_timeout is a PG 17+ parameter and not necessary for init scripts"
                print "-- SET transaction_timeout = 0;"
            } else {
                print $0
            }
        }' "${uncompressed}" > "${uncompressed}.tmp"
        mv "${uncompressed}.tmp" "${uncompressed}"
        timeout_fixed=true
        echo "  ✓ Commented out transaction_timeout"
    else
        echo "  - No transaction_timeout to fix"
    fi

    # Recompress
    gzip "${uncompressed}"

    if [ "$connection_added" = false ] && [ "$timeout_fixed" = false ]; then
        echo "  ℹ No changes needed"
    fi
done

echo ""
echo "=== Fix complete ==="
echo ""
echo "Fixes applied:"
echo "  1. Added \\c bluebox bb_admin (database connection)"
echo "  2. Commented out transaction_timeout (PG 17+ compatibility)"
echo ""
echo "Modified files:"
for file in "${DATA_FILES[@]}"; do
    echo "  - ${file}"
done
echo ""
echo "Backup saved to: ${BACKUP_DIR}"
echo ""
echo "You can now test with: ./scripts/test-build.sh"
